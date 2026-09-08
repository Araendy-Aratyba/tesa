class CreateCamaraVotings < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_votings do |t|
      t.string :external_id, null: false
      t.date :occurred_on, null: false
      t.datetime :registered_at
      t.string :body_external_id
      t.string :body_acronym
      t.string :body_source_uri
      t.string :event_external_id
      t.string :event_source_uri
      t.text :description
      t.boolean :approved
      t.jsonb :raw_payload, null: false
      t.string :source_uri, null: false
      t.datetime :fetched_at, null: false
      t.timestamps

      t.index :external_id, unique: true
      t.index :occurred_on
      t.index :body_external_id
      t.index :event_external_id
      t.check_constraint "btrim(external_id) <> ''", name: "camara_votings_external_id_present"
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'", name: "camara_votings_payload_object"
    end
  end
end
