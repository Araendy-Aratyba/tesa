# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_25_010940) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "camara_sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cursor"
    t.string "error_class"
    t.text "error_message"
    t.integer "failed_count", default: 0, null: false
    t.jsonb "filters", default: {}, null: false
    t.datetime "finished_at"
    t.integer "page"
    t.integer "processed_count", default: 0, null: false
    t.string "resource", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_camara_sync_runs_on_created_at"
    t.index ["resource"], name: "index_camara_sync_runs_on_resource"
    t.index ["status"], name: "index_camara_sync_runs_on_status"
    t.check_constraint "failed_count >= 0", name: "camara_sync_runs_failed_count_nonnegative_check"
    t.check_constraint "jsonb_typeof(filters) = 'object'::text", name: "camara_sync_runs_filters_object_check"
    t.check_constraint "page IS NULL OR page > 0", name: "camara_sync_runs_page_positive_check"
    t.check_constraint "processed_count >= 0", name: "camara_sync_runs_processed_count_nonnegative_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'succeeded'::character varying, 'failed'::character varying]::text[])", name: "camara_sync_runs_status_check"
  end
end
