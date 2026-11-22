# frozen_string_literal: true

class CreateCamaraVotingHydrationFailures < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_voting_hydration_failures do |t|
      t.references :sync_run, null: false, index: false, foreign_key: { to_table: :camara_sync_runs, on_delete: :cascade }
      t.string :voting_external_id, null: false
      t.string :job_id, null: false
      t.integer :attempts, null: false
      t.string :error_class, null: false
      t.timestamps

      t.index [ :sync_run_id, :voting_external_id ], unique: true, name: "index_camara_hydration_failures_identity"
      t.check_constraint "attempts > 0", name: "camara_hydration_failures_attempts_positive"
    end
  end
end
