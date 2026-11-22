class CreateCamaraParties < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_parties do |t|
      t.string :external_id, null: false
      t.string :source_uri, null: false
      t.string :acronym, null: false
      t.string :name, null: false
      t.string :situation
      t.jsonb :raw_payload, null: false
      t.datetime :fetched_at, null: false
      t.jsonb :detail_raw_payload
      t.datetime :detail_fetched_at
      t.timestamps

      t.index :external_id, unique: true
      t.index :acronym
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'", name: "camara_parties_payload_object"
      t.check_constraint "jsonb_typeof(detail_raw_payload) = 'object'", name: "camara_parties_detail_object"
      t.check_constraint "(detail_raw_payload IS NULL) = (detail_fetched_at IS NULL)", name: "camara_parties_detail_provenance"
    end
  end
end
