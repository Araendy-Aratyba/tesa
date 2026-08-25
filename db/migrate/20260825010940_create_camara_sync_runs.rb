class CreateCamaraSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_sync_runs do |t|
      t.string :resource, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :filters, null: false, default: {}
      t.string :cursor
      t.integer :page
      t.integer :processed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.string :error_class
      t.text :error_message

      t.timestamps

      t.index :resource
      t.index :status
      t.index :created_at
      t.check_constraint "status IN ('pending', 'running', 'succeeded', 'failed')",
        name: "camara_sync_runs_status_check"
      t.check_constraint "jsonb_typeof(filters) = 'object'",
        name: "camara_sync_runs_filters_object_check"
      t.check_constraint "page IS NULL OR page > 0",
        name: "camara_sync_runs_page_positive_check"
      t.check_constraint "processed_count >= 0",
        name: "camara_sync_runs_processed_count_nonnegative_check"
      t.check_constraint "failed_count >= 0",
        name: "camara_sync_runs_failed_count_nonnegative_check"
    end
  end
end
