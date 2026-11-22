# frozen_string_literal: true

namespace :camara do
  desc "Enfileira a sincronização anual de votações com um ano de quatro dígitos"
  task :sync_votings, [ :year ] => :environment do |_task, args|
    usage = 'Uso: bin/rails "camara:sync_votings[ANO]"'
    abort usage if args.extras.any?

    service = Camara::Ingestion::StartAnnualVotingSync
    result = service.call(year: args[:year])
    run_info = "sync_run_id=#{result.sync_run_id} status=#{result.status}"

    case result.error
    when :invalid_year
      years = service.supported_years
      abort "Informe um ano de quatro dígitos entre #{years.begin} e #{years.end}.\n#{usage}"
    when :already_active
      abort "Já existe uma sincronização anual ativa. #{run_info}"
    when :enqueue_failed
      abort "A fila não aceitou a primeira página. #{run_info}"
    when nil
      puts "Primeira página enfileirada. #{run_info}"
    end
  end
end
