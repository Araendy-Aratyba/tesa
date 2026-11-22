class CreateCamaraLegislatures < ActiveRecord::Migration[8.1]
  def change
    create_table :camara_legislatures do |t|
      t.string :external_id, null: false
      t.integer :number, null: false
      t.string :source_uri, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :election_year
      t.jsonb :raw_payload, null: false
      t.datetime :fetched_at, null: false
      t.timestamps

      t.index :external_id, unique: true
      t.index [ :starts_on, :ends_on ]
      t.check_constraint "starts_on <= ends_on", name: "camara_legislatures_ordered_dates"
      t.check_constraint "number > 0", name: "camara_legislatures_positive_number"
      t.check_constraint "jsonb_typeof(raw_payload) = 'object'", name: "camara_legislatures_payload_object"
    end
  end
end
