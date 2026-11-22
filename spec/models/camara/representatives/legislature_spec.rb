# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Representatives::Legislature do
  it "includes both official date boundaries and returns overlapping matches" do
    historical = create(:camara_representatives_legislature, starts_on: Date.new(1826, 4, 29), ends_on: Date.new(1830, 4, 24))
    overlapping = create(:camara_representatives_legislature, starts_on: historical.ends_on, ends_on: historical.ends_on + 1.year)

    expect(described_class.covering(historical.starts_on - 1.day)).to be_empty
    expect(described_class.covering(historical.starts_on)).to contain_exactly(historical)
    expect(described_class.covering(historical.ends_on)).to contain_exactly(historical, overlapping)
    expect(described_class.covering(historical.ends_on + 1.day)).to contain_exactly(overlapping)
    expect(historical).to have_attributes(election_year: nil)
  end

  it "validates an inverted interval after a persisted legislature is edited" do
    legislature = create(:camara_representatives_legislature)

    expect(legislature.update(ends_on: legislature.starts_on - 1.day)).to be(false)
    expect(legislature.errors[:ends_on]).to be_present
  end
end
