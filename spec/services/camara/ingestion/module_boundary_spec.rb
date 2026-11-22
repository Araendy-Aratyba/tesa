# frozen_string_literal: true

require "rails_helper"
require "prism"

RSpec.describe "Camara Ingestion and Legislation boundaries" do
  it "keeps qualified model references within their owning module" do
    modules = %w[ingestion legislation]
    violations = modules.flat_map do |owner|
      other = (modules - [ owner ]).sole
      models = Rails.root.glob("app/models/camara/#{other}/**/*.rb").map do |path|
        path.relative_path_from(Rails.root.join("app/models/camara")).to_s.delete_suffix(".rb").camelize
      end

      Rails.root.glob("app/{jobs,services}/camara/#{owner}/**/*.rb").filter_map do |path|
        reference = Prism.parse_file(path.to_s).value.breadth_first_search do |node|
          node.is_a?(Prism::ConstantPathNode) && models.include?(node.slice.gsub(/\s/, "").sub(/\A(?:::)?(?:Camara::)?/, ""))
        end
        "#{path.relative_path_from(Rails.root)}:#{reference.location.start_line} uses #{reference.slice}" if reference
      end
    end

    expect(violations).to be_empty, violations.join("\n")
  end
end
