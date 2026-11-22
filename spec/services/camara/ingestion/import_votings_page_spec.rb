# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::ImportVotingsPage do
  # A transaction around the example would hide the commit boundary under test.
  self.use_transactional_tests = false
  include ActiveSupport::Testing::TimeHelpers

  let!(:sync_run) { create(:camara_ingestion_sync_run, :running, filters: { "start_date" => "2026-01-01", "end_date" => "2026-12-31", "items_per_page" => 2 }) }
  let(:external_ids) { Array.new(2) { "import-#{SecureRandom.uuid}" } }
  let(:client) { CongregaPlenum::VotingsService }
  let(:first_payload) do
    {
      "id" => external_ids.first,
      "data" => "2026-08-04",
      "uri" => "https://example.org/votacoes/#{external_ids.first}",
      "descricao" => "Deliberação inicial"
    }
  end
  let(:second_payload) { first_payload.merge("id" => external_ids.last) }

  before do
    allow(client).to receive(:fetch_list).and_raise("unexpected voting request")
  end

  after do
    Camara::Legislation::Voting.where(external_id: external_ids).delete_all
    sync_run.destroy!
  end

  def page_request(page)
    allow(client).to receive(:fetch_list).with(
      page:, items_per_page: 2, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31)
    )
  end

  def import(page = 1, **options)
    described_class.call(**{ sync_run_id: sync_run.id, page:, items_per_page: 2 }.merge(options))
  end

  it "fetches outside a transaction and reports the likely next page after a full page" do
    page_request(1).and_invoke(lambda do |**_|
      expect(ApplicationRecord.current_transaction).not_to be_open
      [ first_payload, second_payload ]
    end)

    result = import

    expect(result).to have_attributes(received_count: 2, persisted_count: 2, voting_ids: external_ids, next_page: 2)
    expect(result.voting_ids).to be_frozen
    expect(result.voting_ids).to all(be_frozen)
    expect(Camara::Legislation::Voting.where(external_id: external_ids).count).to eq(2)
    expect(sync_run.reload).to have_attributes(page: 1, processed_count: 2, status: "running")
  end

  it "replays a page without duplicating records or counting it twice and applies a correction" do
    page_request(1).and_return([ first_payload ])

    travel_to(Time.utc(2026, 8, 5)) { import }
    original = Camara::Legislation::Voting.find_by!(external_id: external_ids.first)
    corrected = first_payload.merge("descricao" => "Informação corrigida", "aprovacao" => 1)
    page_request(1).and_return([ corrected ])

    result = travel_to(Time.utc(2026, 8, 6)) { import }

    expect(result.next_page).to be_nil
    expect(original.reload).to have_attributes(
      description: "Informação corrigida", approved: true, raw_payload: corrected, fetched_at: Time.utc(2026, 8, 6)
    )
    expect(Camara::Legislation::Voting.where(external_id: external_ids).count).to eq(1)
    expect(sync_run.reload).to have_attributes(page: 1, processed_count: 1)
  end

  it "records an empty page without adding records or scheduling another page" do
    page_request(1).and_return([ first_payload, second_payload ])
    page_request(2).and_return([])
    import

    expect(import(2)).to have_attributes(received_count: 0, persisted_count: 0, voting_ids: [], next_page: nil)
    expect(sync_run.reload).to have_attributes(page: 2, processed_count: 2)
  end

  it "propagates an HTTP failure without writes or progress" do
    page_request(1).and_raise(CongregaPlenum::APIError, "source unavailable")

    expect { import }.to raise_error(CongregaPlenum::APIError, "source unavailable")
    expect(Camara::Legislation::Voting.where(external_id: external_ids)).to be_empty
    expect(sync_run.reload).to have_attributes(page: nil, processed_count: 0, status: "running")
  end

  it "maps the entire page before persisting when one record is invalid" do
    page_request(1).and_return([ first_payload, second_payload.except("data") ])

    expect { import }.to raise_error(Camara::Legislation::Mappers::ContractError, /voting\.data/)
    expect(Camara::Legislation::Voting.where(external_id: external_ids)).to be_empty
    expect(sync_run.reload.page).to be_nil
  end

  it "rejects a malformed collection received from the client" do
    page_request(1).and_return(nil)

    expect { import }.to raise_error(described_class::InvalidResponse)
    expect(sync_run.reload.page).to be_nil
  end

  it "rejects duplicate identities within the same page without advancing progress" do
    page_request(1).and_return([ first_payload, first_payload ])

    expect { import }.to raise_error(Camara::Legislation::Mappers::ContractError, /votings\.id/)
    expect(Camara::Legislation::Voting.where(external_id: external_ids)).to be_empty
    expect(sync_run.reload.page).to be_nil
  end

  it "keeps the whole page and checkpoint unchanged if PostgreSQL rejects a record" do
    page_request(1).and_return([ first_payload, second_payload.merge("campoNovo" => "\0") ])

    expect { import }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Camara::Legislation::Voting.where(external_id: external_ids)).to be_empty
    expect(sync_run.reload).to have_attributes(page: nil, processed_count: 0)
  end

  it "keeps the page committed when the run stops before the checkpoint can be recorded" do
    page_request(1).and_invoke(lambda do |**_|
      sync_run.fail!(error: RuntimeError.new("cancelled during fetch"))
      [ first_payload ]
    end)

    expect { import }.to raise_error(Camara::Ingestion::SyncRun::InvalidTransition)
    expect(Camara::Legislation::Voting.find_by!(external_id: external_ids.first).raw_payload).to eq(first_payload)
    expect(sync_run.reload).to have_attributes(page: nil, processed_count: 0, status: "failed")
  end

  it "rejects a date range that crosses a calendar year" do
    sync_run.update!(filters: sync_run.filters.merge("start_date" => "2026-12-31", "end_date" => "2027-01-01"))

    expect { import }.to raise_error(described_class::InvalidRequest, /calendar year/)
  end

  it "rejects page sizes beyond the client contract and pages that skip the checkpoint" do
    expect { import(1, items_per_page: 3) }.to raise_error(described_class::InvalidRequest, /match the sync filters/)
    expect { import(2) }.to raise_error(described_class::InvalidRequest, /skip the checkpoint/)

    sync_run.update!(filters: sync_run.filters.merge("items_per_page" => 101))
    expect { import }.to raise_error(described_class::InvalidRequest, /invalid number of items per page/)
  end

  it "rejects a call inside an existing database transaction" do
    ApplicationRecord.transaction do
      expect { import }.to raise_error(described_class::InvalidRequest, /outside a database transaction/)
    end
  end
end
