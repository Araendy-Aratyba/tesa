# frozen_string_literal: true

abort "Use CAMARA_LIVE_PILOT=1 em desenvolvimento com um banco descartável." unless
  Rails.env.development? && ENV["CAMARA_LIVE_PILOT"] == "1"

unless ARGV.one? && ARGV.first.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
  abort "Informe uma data no formato AAAA-MM-DD."
end

begin
  date = Date.iso8601(ARGV.first)
rescue Date::Error
  abort "Informe uma data civil válida."
end
abort "Escolha um dia já encerrado." unless date < Date.current

if Camara::Ingestion::SyncRun.exists? || Camara::Legislation::Voting.exists?
  abort "Use um banco descartável e vazio de votações e execuções."
end

max_votings = 8
CongregaPlenum.configuration.retries = 0
CongregaPlenum.configuration.timeout = 10

# Run only this pilot's jobs and stop if any job schedules a retry.
ActiveJob::Base.queue_adapter = :test
jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
ingestion = Camara::Ingestion::PublicApi
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
run = Camara::Ingestion::SyncRun.create!(
  resource: "votings", filters: { "start_date" => date.iso8601, "end_date" => date.iso8601, "max_pages" => 1 }
)
ingestion.start!(sync_run_id: run.id)

begin
  unless Camara::Ingestion::SyncVotingsPageJob.perform_later(sync_run_id: run.id, page: 1)
    raise "A fila do piloto rejeitou a primeira página."
  end
  ActiveJob::Base.execute(jobs.shift)
  checkpoint = ingestion.fetch(sync_run_id: run.id)
  unless checkpoint.page == 1 && checkpoint.pagination_completed_at && checkpoint.pending_voting_ids.nil? &&
      jobs.size.between?(1, max_votings) && jobs.size == checkpoint.processed_count && jobs.all? { |job|
        job[:job] == Camara::Legislation::HydrateVotingJob && job[:at].nil?
      }
    raise "A janela deve retornar uma página concluída com 1 a #{max_votings} votações."
  end

  outcomes = jobs.shift(jobs.size).map do |job|
    result = ActiveJob::Base.execute(job)
    raise "Hidratação não concluída; retentativas ficam fora do piloto." unless jobs.empty? && result.respond_to?(:status) && result.status == :hydrated

    voting = Camara::Legislation::Voting.find_by!(external_id: result.external_id)
    unless voting.occurred_on == date && voting.raw_payload.fetch("id") == voting.external_id &&
        voting.detail_raw_payload.fetch("id") == voting.external_id && voting.detail_hydrated_at &&
        voting.votes_hydrated_at && voting.orientations_hydrated_at &&
        voting.votes.count == result.votes.count && voting.orientations.count == result.orientations.count
      raise "A persistência da votação #{voting.external_id} divergiu do resultado da hidratação."
    end

    { id: voting.external_id, approved: voting.approved, votes: result.votes.count, orientations: result.orientations.count }
  end

  unless ingestion.fetch(sync_run_id: run.id).failed_count.zero? && outcomes.pluck(:id).uniq.size == checkpoint.processed_count
    raise "A auditoria do piloto divergiu das hidratações concluídas."
  end

  completed = ingestion.succeed!(sync_run_id: run.id)
  puts JSON.generate(
    date: date.iso8601, sync_run_id: run.id, status: completed.status, pages: completed.page,
    processed_count: completed.processed_count, failed_count: completed.failed_count,
    duration_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(2), votings: outcomes
  )
rescue StandardError => error
  ingestion.fail_running!(sync_run_id: run.id, error:)
  warn "Piloto interrompido. sync_run_id=#{run.id}"
  raise
end
