# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::PaginateVotings do
  # Exercise the real commit boundary before the checkpoint update.
  self.use_transactional_tests = false
  include ActiveSupport::Testing::TimeHelpers

  let!(:sync_run) { create(:camara_ingestion_sync_run, :running) }
  let(:client) { CongregaPlenum::VotingsService }
  let(:ids) { Array.new(100) { "pagination-#{SecureRandom.uuid}" } }
  let(:full_page) do
    ids.map do |id|
      { "id" => id, "data" => "2026-01-05", "uri" => "https://example.org/votacoes/#{id}" }
    end
  end

  before do
    allow(client).to receive(:fetch_list).and_raise("unexpected voting page request")
  end

  after do
    Camara::Legislation::Voting.where(external_id: ids).delete_all
    sync_run.destroy!
  end

  def request(page, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), order: "ASC", order_by: "id")
    allow(client).to receive(:fetch_list).with(page:, items_per_page: 100, start_date:, end_date:, order:, order_by:)
  end

  def paginate
    described_class.call(sync_run_id: sync_run.id)
  end

  it "records the last empty page after a full page and stays complete on subsequent calls" do
    request(1).and_return(full_page)
    request(2).and_return([])

    expect(paginate).to have_attributes(status: :continue, page: 1, next_page: 2)
    expect(sync_run.reload.filters).to include("order" => "ASC", "order_by" => "id", "items_per_page" => 100)
    expect(paginate).to have_attributes(status: :complete, page: 2, next_page: nil)
    expect(sync_run.reload).to have_attributes(page: 2, processed_count: 100, status: "running")
    expect(sync_run.pagination_completed_at).to be_present

    request(2).and_raise("a confirmed page must not be fetched again")
    expect(paginate).to have_attributes(status: :complete, page: nil, next_page: nil)
  end

  it "retries only the unconfirmed page and upserts a correction duplicated across pages" do
    request(1).and_return(full_page)
    request(2).and_raise(CongregaPlenum::APIError, "source unavailable")
    paginate

    expect { paginate }.to raise_error(CongregaPlenum::APIError)
    expect(sync_run.reload).to have_attributes(page: 1, processed_count: 100, pagination_completed_at: nil)
    request(1).and_raise("a confirmed page must not be fetched again")
    request(2).and_return([ full_page.first.merge("descricao" => "Corrigida") ])

    expect(paginate).to have_attributes(status: :complete, page: 2, next_page: nil)
    expect(Camara::Legislation::Voting.where(external_id: ids).count).to eq(100)
    expect(Camara::Legislation::Voting.find_by!(external_id: ids.first).description).to eq("Corrigida")
    expect(sync_run.reload.processed_count).to eq(101)
  end

  it "honors the persisted cap even when the provider repeats a full page" do
    sync_run.update!(filters: sync_run.filters.merge("max_pages" => 2))
    request(1).and_return(full_page)
    request(2).and_return(full_page)

    expect(paginate).to have_attributes(status: :continue, next_page: 2)
    expect(paginate).to have_attributes(status: :page_limit_reached, page: 2, next_page: nil)
    expect(paginate).to have_attributes(status: :page_limit_reached, page: nil, next_page: nil)
    expect(sync_run.reload).to have_attributes(page: 2, pagination_completed_at: nil)
    expect(Camara::Legislation::Voting.where(external_id: ids).count).to eq(100)
  end

  it "freezes a named incremental window in the current year before fetching, even on a failed attempt" do
    sync_run.update!(filters: { "mode" => "incremental" })
    dates = { start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 8) }
    request(1, **dates).and_raise(CongregaPlenum::APIError)

    travel_to(Time.utc(2026, 1, 8, 12)) do
      expect { paginate }.to raise_error(CongregaPlenum::APIError)
    end

    expect(sync_run.reload.filters).to include("start_date" => "2026-01-01", "end_date" => "2026-01-08")
    request(1, **dates).and_return([])
    travel_to(Time.utc(2026, 1, 9, 12)) do
      expect(paginate).to have_attributes(status: :complete, page: 1)
    end
  end

  it "preserves the implicit provider order of a checkpoint created before ordering was recorded" do
    sync_run.update!(page: 1, processed_count: 100)
    request(2, order: "DESC", order_by: "dataHoraRegistro").and_return([])

    expect(paginate).to have_attributes(status: :complete, page: 2)
    expect(sync_run.reload.filters).to include("order" => "DESC", "order_by" => "dataHoraRegistro")
  end

  it "rejects a range crossing calendar years without changing progress or run filters" do
    filters = { "start_date" => "2026-12-31", "end_date" => "2027-01-01" }
    sync_run.update!(filters:)

    expect { paginate }.to raise_error(Camara::Ingestion::VotingsDateRange::InvalidRange, /calendar year/)
    expect(sync_run.reload).to have_attributes(page: nil, filters:)
  end

  it "rejects invalid limits and unsupported ordering before fetching" do
    original = sync_run.filters
    sync_run.update!(filters: original.merge("max_pages" => 0))
    expect { paginate }.to raise_error(described_class::InvalidRequest, /max_pages/)

    sync_run.update!(filters: original.merge("order" => "DESC", "order_by" => "data"))
    expect { paginate }.to raise_error(described_class::InvalidRequest, /unsupported/)
  end
end
