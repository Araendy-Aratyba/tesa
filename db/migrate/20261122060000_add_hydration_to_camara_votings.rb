# frozen_string_literal: true

class AddHydrationToCamaraVotings < ActiveRecord::Migration[8.1]
  def change
    add_column :camara_votings, :detail_raw_payload, :jsonb
    add_column :camara_votings, :detail_hydrated_at, :datetime
    add_column :camara_votings, :votes_hydrated_at, :datetime
    add_column :camara_votings, :orientations_hydrated_at, :datetime
  end
end
