# frozen_string_literal: true

class AddPaginationCompletedAtToCamaraSyncRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :camara_sync_runs, :pagination_completed_at, :datetime
  end
end
