# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Legislation::Orientation, type: :model do
  it "persists group identity, source snapshot and orientation independently" do
    orientation = create(:camara_legislation_orientation, :released)

    expect(orientation.reload).to have_attributes(
      leadership_type: "P",
      position: "Liberado",
      group_acronym: orientation.group_acronym,
      group_external_id: orientation.group_external_id,
      group_source_uri: orientation.group_source_uri
    )
    expect(orientation.group_key).to start_with("uri:https://")
  end

  it "preserves unknown payload fields and an unknown orientation without inventing a meaning" do
    payload = { "orientacaoVoto" => nil, "regraNova" => [ "valor" ] }
    orientation = create(
      :camara_legislation_orientation,
      :position_unknown,
      :without_group_uri,
      raw_payload: payload
    )
    blank = create(
      :camara_legislation_orientation,
      position: "",
      voting: orientation.voting
    )

    expect(orientation.reload.position).to be_nil
    expect(orientation.raw_payload).to eq(payload)
    expect(orientation.group_key).to eq("leadership:P:#{orientation.group_acronym}")
    expect(blank.reload.position).to eq("")
  end

  %i[voting group_key fetched_at raw_payload].each do |attribute|
    it "rejects a missing #{attribute}" do
      orientation = create(:camara_legislation_orientation)

      expect(orientation.update(attribute => nil)).to be(false)
      expect(orientation.errors[attribute]).to be_present
      expect(orientation.reload.public_send(attribute)).to be_present
    end
  end

  it "rejects a non-object raw payload" do
    orientation = create(:camara_legislation_orientation)

    expect(orientation.update(raw_payload: [ "invalid" ])).to be(false)
    expect(orientation.errors[:raw_payload]).to include("must be a JSON object")
    expect(orientation.reload.raw_payload).to be_a(Hash)
  end

  it "enforces one orientation per group and voting in validations and PostgreSQL" do
    voting = create(:camara_legislation_voting)
    orientation, other = create_list(:camara_legislation_orientation, 2, voting:)

    expect(other.update(group_key: orientation.group_key)).to be(false)
    expect(other.errors[:group_key]).to include("has already been taken")

    same_group_elsewhere = create(
      :camara_legislation_orientation,
      group_key: orientation.group_key
    )
    expect(same_group_elsewhere).to be_persisted

    expect do
      described_class.insert_all!([ orientation.attributes.except("id") ])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "updates a reimported orientation through the composite identity without duplicating it" do
    orientation = create(:camara_legislation_orientation, position: "Sim")
    newer_payload = orientation.raw_payload.merge("orientacaoVoto" => "Não", "campoNovo" => true)

    described_class.upsert_all(
      [
        orientation.attributes.except("id", "created_at", "updated_at").merge(
          "position" => "Não",
          "raw_payload" => newer_payload,
          "fetched_at" => 1.hour.from_now
        )
      ],
      unique_by: :index_camara_orientations_identity
    )

    expect(described_class.where(voting: orientation.voting, group_key: orientation.group_key).count).to eq(1)
    expect(orientation.reload).to have_attributes(position: "Não", raw_payload: newer_payload)
  end

  it "has the indexes required for identity and filtering" do
    indexes = described_class.connection.indexes(described_class.table_name)

    identity = indexes.find { |index| index.name == "index_camara_orientations_identity" }
    expect(identity.columns).to eq(%w[voting_id group_key])
    expect(identity.unique).to be(true)
    expect(indexes.map(&:columns)).to include([ "group_key" ], [ "position" ])
  end
end
