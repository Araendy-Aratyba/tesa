# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Legislation::HydrateVotingJob, type: :job do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let!(:sync_run) { create(:camara_ingestion_sync_run, :running) }
  let!(:voting) { create(:camara_legislation_voting) }
  let(:client) { CongregaPlenum::Client.instance }
  let(:endpoint) { "votacoes/#{voting.external_id}" }
  let(:arguments) { { external_id: voting.external_id, sync_run_id: sync_run.id } }
  let(:job) { described_class.new(**arguments) }

  before do
    allow(client).to receive(:get).and_raise("unexpected Câmara request")
    allow(client).to receive(:get).with(endpoint, {}).and_return("dados" => voting.raw_payload)
    allow(client).to receive(:get).with("#{endpoint}/votos", {}).and_return(
      "dados" => [ { "tipoVoto" => "Sim", "deputado_" => { "id" => 999 } } ]
    )
    allow(client).to receive(:get).with("#{endpoint}/orientacoes", {}).and_return(
      "dados" => [ { "orientacaoVoto" => "Liberado", "codTipoLideranca" => "G", "siglaPartidoBloco" => "Governo" } ]
    )
  end

  after do
    voting.destroy!
    sync_run.destroy!
  end

  [ CongregaPlenum::ConnectionError, CongregaPlenum::RateLimitError, CongregaPlenum::ServerError ].each do |error_class|
    it "retries #{error_class.name} from the detail request with a delay" do
      allow(client).to receive(:get).with(endpoint, {}).and_raise(error_class)

      freeze_time do
        expect { job.perform_now }.to have_enqueued_job(described_class).with(**arguments).on_queue("camara_hydration")
        expect(enqueued_jobs.last.fetch(:at)).to be > Time.current.to_f
      end
      expect(sync_run.reload.failed_count).to eq(0)
    end
  end

  it "backs off and records a terminal failure only after three attempts" do
    summary = voting.raw_payload
    allow(client).to receive(:get).with("#{endpoint}/votos", {}).and_raise(CongregaPlenum::ServerError)

    freeze_time do
      job.perform_now
      first_retry = enqueued_jobs.last
      ActiveJob::Base.execute(first_retry)
      last_retry = enqueued_jobs.last
      expect(last_retry.fetch(:at)).to be > first_retry.fetch(:at)
      expect(sync_run.reload.failed_count).to eq(0)

      expect { ActiveJob::Base.execute(last_retry) }.to raise_error(CongregaPlenum::ServerError)
      expect { ActiveJob::Base.execute(last_retry) }.to raise_error(CongregaPlenum::ServerError)
    end

    expect(enqueued_jobs.size).to eq(2)
    expect(sync_run.reload).to have_attributes(failed_count: 1, status: "running")
    expect(sync_run.voting_hydration_failures.sole).to have_attributes(
      voting_external_id: voting.external_id, job_id: job.job_id, attempts: 3, error_class: "CongregaPlenum::ServerError"
    )
    expect(voting.reload).to have_attributes(raw_payload: summary, detail_hydrated_at: nil)
  end

  it "records a permanent HTTP error on the first attempt and leaves it visible to the queue" do
    allow(client).to receive(:get).with(endpoint, {}).and_raise(CongregaPlenum::APIError, "HTTP Error 404")

    expect { job.perform_now }.to raise_error(Camara::Ingestion::HydrateVoting::FetchError)
    expect(enqueued_jobs).to be_empty
    expect(sync_run.voting_hydration_failures.sole).to have_attributes(attempts: 1, error_class: "CongregaPlenum::APIError")
  end

  it "does not retry invalid payloads or overwrite a previously hydrated vote" do
    job.perform_now
    previous_vote = voting.votes.sole
    allow(client).to receive(:get).with("#{endpoint}/votos", {}).and_return("dados" => [ {} ])

    expect { described_class.perform_now(**arguments) }.to raise_error(Camara::Legislation::Mappers::ContractError)
    expect(enqueued_jobs).to be_empty
    expect(sync_run.voting_hydration_failures.sole.attempts).to eq(1)
    expect(voting.votes.reload).to contain_exactly(previous_vote)
  end

  it "recovers on retry and reexecutes without duplicating votes or orientations" do
    allow(client).to receive(:get).with(endpoint, {}).and_raise(CongregaPlenum::ConnectionError)
    job.perform_now
    allow(client).to receive(:get).with(endpoint, {}).and_return("dados" => voting.raw_payload)

    ActiveJob::Base.execute(enqueued_jobs.last)
    vote = voting.votes.sole
    orientation = voting.orientations.sole
    described_class.perform_now(**arguments)

    expect(voting.votes.reload).to contain_exactly(vote)
    expect(voting.orientations.reload).to contain_exactly(orientation)
    expect(sync_run.reload.failed_count).to eq(0)
  end

  it "uses one Solid Queue slot per voting across runs and accepts already serialized jobs" do
    legacy = Camara::Ingestion::HydrateVotingJob.new(external_id: voting.external_id)
    same_voting = described_class.new(**arguments.merge(sync_run_id: sync_run.id + 1))
    different_voting = described_class.new(**arguments.merge(external_id: "another-voting"))

    expect(job).to have_attributes(concurrency_limit: 1, concurrency_on_conflict: :block)
    expect(job.concurrency_key).to eq(same_voting.concurrency_key).and eq(legacy.concurrency_key)
    expect(job.concurrency_key).not_to eq(different_voting.concurrency_key)

    ActiveJob::Base.execute(legacy.serialize)
    expect(voting.reload.detail_hydrated_at).to be_present
  end
end
