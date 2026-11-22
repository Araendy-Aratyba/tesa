# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Camara annual voting sync" do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:ingestion) { Camara::Ingestion::PublicApi }
  let(:scope) { Camara::Legislation::Voting.where(external_id: (full_page + [ unknown ]).pluck("id")) }
  let(:nominal) { fixture("voting_summary") }
  let(:symbolic) { summary("integration-symbolic") }
  let(:unknown) { summary("integration-unknown") }
  let(:full_page) { [ nominal, symbolic ] + Array.new(98) { |index| summary("integration-#{index}") } }
  let(:responses) { {} }
  let(:run_ids) { [] }

  around { |example| travel_to(Time.utc(2026, 11, 22, 12)) { example.run } }

  before do
    allow(CongregaPlenum::Client.instance).to receive(:get) do |endpoint, params|
      response = responses.fetch([ endpoint, params ])
      response.respond_to?(:call) ? response.call : response
    end
  end

  after do
    scope.destroy_all
    Camara::Ingestion::SyncRun.where(id: run_ids).delete_all
  end

  def fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/camara/legislation/#{name}.json").read)
  end

  def summary(id)
    nominal.merge("id" => id, "uri" => "https://dadosabertos.camara.leg.br/api/v2/votacoes/#{id}")
  end

  def page_request(page)
    [ "votacoes", { dataInicio: "2026-01-01", dataFim: "2026-12-31", pagina: page, itens: 100, ordem: "ASC", ordenarPor: "id" } ]
  end

  def source_page(page, payloads, &failure)
    responses[page_request(page)] = failure || { "dados" => payloads }
    payloads.each do |summary|
      id = summary.fetch("id")
      endpoint = "votacoes/#{id}"
      detail = summary.merge("aprovacao" => (1 if summary == symbolic))
      detail = fixture("voting_detail") if summary == nominal
      responses[[ endpoint, {} ]] = { "dados" => detail }
      responses[[ "#{endpoint}/votos", {} ]] = { "dados" => (summary == nominal ? [ fixture("vote") ] : []) }
      responses[[ "#{endpoint}/orientacoes", {} ]] = { "dados" => (summary == nominal ? [ fixture("orientation") ] : []) }
    end
  end

  def start_sync
    result = Camara::Ingestion::StartAnnualVotingSync.call(year: "2026")
    run_ids << result.sync_run_id if result.sync_run_id
    expect(result).to have_attributes(status: :running, error: nil)
    result.sync_run_id
  end

  def next_job
    ActiveJob::Base.execute(enqueued_jobs.shift)
  end

  def drain_jobs
    next_job until enqueued_jobs.empty?
  end

  it "hydrates nominal and symbolic decisions and applies corrections across a full replay" do
    source_page(1, [ nominal, symbolic, unknown ])
    first_run_id = start_sync
    drain_jobs

    expect(ingestion.fetch(sync_run_id: first_run_id)).to have_attributes(
      status: "running", page: 1, processed_count: 3, failed_count: 0,
      pagination_completed_at: be_present, pending_voting_ids: nil
    )
    nominal_record = scope.find_by!(external_id: "0001234-35")
    vote = nominal_record.votes.sole
    orientation = nominal_record.orientations.sole
    symbolic_record = scope.find_by!(external_id: symbolic.fetch("id"))
    unknown_record = scope.find_by!(external_id: unknown.fetch("id"))
    expect(nominal_record.approved).to be(false)
    expect(symbolic_record).to have_attributes(approved: true, votes_hydrated_at: be_present)
    expect(symbolic_record.votes).to be_empty
    expect(unknown_record.approved).to be_nil

    ingestion.succeed!(sync_run_id: first_run_id)
    endpoint = "votacoes/#{nominal_record.external_id}"
    corrected_detail = fixture("voting_detail").merge("aprovacao" => 1, "descricao" => "Resultado corrigido pela Câmara.")
    responses[[ endpoint, {} ]] = { "dados" => corrected_detail }
    responses[[ "#{endpoint}/votos", {} ]] = { "dados" => [ fixture("vote").merge("tipoVoto" => "Sim") ] }
    responses[[ "#{endpoint}/orientacoes", {} ]] = { "dados" => [ fixture("orientation").merge("orientacaoVoto" => "Sim") ] }

    second_run_id = start_sync
    drain_jobs

    expect(scope).to contain_exactly(nominal_record, symbolic_record, unknown_record)
    expect(nominal_record.reload).to have_attributes(approved: true, detail_raw_payload: corrected_detail, raw_payload: nominal)
    expect(nominal_record.votes.reload).to contain_exactly(vote)
    expect(nominal_record.orientations.reload).to contain_exactly(orientation)
    expect(Camara::Legislation::Vote.where(voting_id: scope).count).to eq(1)
    expect(Camara::Legislation::Orientation.where(voting_id: scope).count).to eq(1)
    expect(vote.reload.position).to eq("Sim")
    expect(orientation.reload.position).to eq("Sim")
    expect(ingestion.fetch(sync_run_id: second_run_id)).to have_attributes(processed_count: 3, failed_count: 0)
  end

  it "resumes a transient failure on the second page without repeating the confirmed page" do
    source_page(1, full_page)
    source_page(2, [ unknown ]) { raise CongregaPlenum::ServerError, "HTTP 503" }
    run_id = start_sync
    next_job
    full_page.size.times { next_job }
    next_job

    expect(ingestion.fetch(sync_run_id: run_id)).to have_attributes(
      status: "running", page: 1, processed_count: 100, failed_count: 0, pagination_completed_at: nil
    )
    expect(scope.count).to eq(100)
    expect(scope.find_by!(external_id: nominal.fetch("id")).votes.count).to eq(1)
    expect(enqueued_jobs.sole).to include(job: Camara::Ingestion::SyncVotingsPageJob, at: be > Time.current.to_f)

    responses.delete(page_request(1))
    source_page(2, [ unknown ])
    drain_jobs

    expect(ingestion.fetch(sync_run_id: run_id)).to have_attributes(
      status: "running", page: 2, processed_count: 101, failed_count: 0,
      pagination_completed_at: be_present, pending_voting_ids: nil
    )
    expect(scope.count).to eq(101)
    expect(scope.find_by!(external_id: unknown.fetch("id"))).to have_attributes(approved: nil, detail_hydrated_at: be_present)
  end

  it "keeps confirmed parents and children visible after a permanent failure on an intermediate page" do
    source_page(1, full_page)
    source_page(2, []) { raise CongregaPlenum::APIError, "HTTP 404" }
    run_id = start_sync
    next_job
    full_page.size.times { next_job }

    expect { next_job }.to raise_error(CongregaPlenum::APIError)

    expect(enqueued_jobs).to be_empty
    expect(ingestion.fetch(sync_run_id: run_id)).to have_attributes(
      status: "failed", page: 1, processed_count: 100, pagination_completed_at: nil, error_class: "CongregaPlenum::APIError"
    )
    expect(scope.count).to eq(100)
    record = scope.find_by!(external_id: nominal.fetch("id"))
    expect(record).to have_attributes(raw_payload: nominal, detail_raw_payload: fixture("voting_detail"))
    expect(record.votes.size).to eq(1)
    expect(record.orientations.size).to eq(1)
  end
end
