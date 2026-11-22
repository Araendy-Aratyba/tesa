class CreateCamaraDeputies < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_deputies do |t|
      t.string :external_id, null: false
      t.string :source_uri, null: false
      t.string :civil_name
      t.string :electoral_name
      t.string :state_acronym
      t.string :situation
      t.string :party_acronym
      t.string :party_source_uri
      t.string :current_legislature_external_id
      t.jsonb :raw_payload
      t.datetime :fetched_at
      t.timestamps

      t.index :external_id, unique: true
      t.index "lower(electoral_name)", name: "index_camara_deputies_on_lower_electoral_name"
      t.index :state_acronym
      t.index :situation
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'", name: "camara_deputies_payload_object"
      t.check_constraint "(raw_payload IS NULL) = (fetched_at IS NULL)", name: "camara_deputies_detail_provenance"
    end

    create_table :camara_deputy_listing_observations do |t|
      t.references :deputy, null: false, index: false, foreign_key: { to_table: :camara_deputies, on_delete: :cascade }
      t.string :legislature_external_id, null: false
      t.string :payload_fingerprint, null: false, limit: 64
      t.jsonb :raw_payload, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps

      t.index [ :deputy_id, :legislature_external_id, :payload_fingerprint ], name: "index_camara_deputy_listing_identity", unique: true
      t.index :legislature_external_id, name: "index_camara_deputy_listings_on_legislature_external_id"
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'", name: "camara_deputy_listing_payload_object"
      t.check_constraint "first_seen_at <= last_seen_at", name: "camara_deputy_listing_ordered_observation"
    end
  end
end
