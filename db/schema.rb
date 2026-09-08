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

ActiveRecord::Schema[8.1].define(version: 2026_09_08_003000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "camara_orientations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.string "group_acronym"
    t.string "group_external_id"
    t.string "group_key", null: false
    t.string "group_source_uri"
    t.string "leadership_type"
    t.string "position"
    t.jsonb "raw_payload", null: false
    t.datetime "updated_at", null: false
    t.bigint "voting_id", null: false
    t.index ["group_key"], name: "index_camara_orientations_on_group_key"
    t.index ["position"], name: "index_camara_orientations_on_position"
    t.index ["voting_id", "group_key"], name: "index_camara_orientations_identity", unique: true
    t.check_constraint "btrim(group_key::text) <> ''::text", name: "camara_orientations_group_key_present"
    t.check_constraint "jsonb_typeof(raw_payload) = 'object'::text", name: "camara_orientations_payload_object"
  end

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
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text])", name: "camara_sync_runs_status_check"
  end

  create_table "camara_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "deputy_email"
    t.string "deputy_external_id", null: false
    t.string "deputy_name"
    t.string "deputy_photo_url"
    t.string "deputy_source_uri"
    t.datetime "fetched_at", null: false
    t.string "legislature_external_id"
    t.string "party_acronym"
    t.string "party_source_uri"
    t.string "position"
    t.jsonb "raw_payload", null: false
    t.datetime "recorded_at"
    t.string "state_acronym"
    t.datetime "updated_at", null: false
    t.bigint "voting_id", null: false
    t.index ["deputy_external_id"], name: "index_camara_votes_on_deputy_external_id"
    t.index ["position"], name: "index_camara_votes_on_position"
    t.index ["voting_id", "deputy_external_id"], name: "index_camara_votes_identity", unique: true
    t.check_constraint "btrim(deputy_external_id::text) <> ''::text", name: "camara_votes_deputy_external_id_present"
    t.check_constraint "jsonb_typeof(raw_payload) = 'object'::text", name: "camara_votes_payload_object"
  end

  create_table "camara_votings", force: :cascade do |t|
    t.boolean "approved"
    t.string "body_acronym"
    t.string "body_external_id"
    t.string "body_source_uri"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "event_external_id"
    t.string "event_source_uri"
    t.string "external_id", null: false
    t.datetime "fetched_at", null: false
    t.date "occurred_on", null: false
    t.jsonb "raw_payload", null: false
    t.datetime "registered_at"
    t.string "source_uri", null: false
    t.datetime "updated_at", null: false
    t.index ["body_external_id"], name: "index_camara_votings_on_body_external_id"
    t.index ["event_external_id"], name: "index_camara_votings_on_event_external_id"
    t.index ["external_id"], name: "index_camara_votings_on_external_id", unique: true
    t.index ["occurred_on"], name: "index_camara_votings_on_occurred_on"
    t.check_constraint "btrim(external_id::text) <> ''::text", name: "camara_votings_external_id_present"
    t.check_constraint "jsonb_typeof(raw_payload) = 'object'::text", name: "camara_votings_payload_object"
  end

  add_foreign_key "camara_orientations", "camara_votings", column: "voting_id"
  add_foreign_key "camara_votes", "camara_votings", column: "voting_id"
end
