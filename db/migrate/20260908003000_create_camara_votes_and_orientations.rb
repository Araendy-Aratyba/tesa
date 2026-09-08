class CreateCamaraVotesAndOrientations < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_votes do |t|
      t.references :voting,
        null: false,
        index: false,
        foreign_key: { to_table: :camara_votings }
      t.string :deputy_external_id, null: false
      t.string :position
      t.datetime :recorded_at
      t.string :deputy_source_uri
      t.string :deputy_name
      t.string :party_acronym
      t.string :party_source_uri
      t.string :state_acronym
      t.string :legislature_external_id
      t.string :deputy_photo_url
      t.string :deputy_email
      t.jsonb :raw_payload, null: false
      t.datetime :fetched_at, null: false
      t.timestamps

      t.index [ :voting_id, :deputy_external_id ],
        unique: true,
        name: "index_camara_votes_identity"
      t.index :deputy_external_id
      t.index :position
      t.check_constraint "btrim(deputy_external_id) <> ''",
        name: "camara_votes_deputy_external_id_present"
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'",
        name: "camara_votes_payload_object"
    end

    create_table :camara_orientations do |t|
      t.references :voting,
        null: false,
        index: false,
        foreign_key: { to_table: :camara_votings }
      t.string :group_key, null: false
      t.string :leadership_type
      t.string :group_acronym
      t.string :group_external_id
      t.string :group_source_uri
      t.string :position
      t.jsonb :raw_payload, null: false
      t.datetime :fetched_at, null: false
      t.timestamps

      t.index [ :voting_id, :group_key ],
        unique: true,
        name: "index_camara_orientations_identity"
      t.index :group_key
      t.index :position
      t.check_constraint "btrim(group_key) <> ''",
        name: "camara_orientations_group_key_present"
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'",
        name: "camara_orientations_payload_object"
    end
  end
end
