# frozen_string_literal: true

class AddPendingVotingIdsToCamaraSyncRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :camara_sync_runs, :pending_voting_ids, :jsonb
  end
end
