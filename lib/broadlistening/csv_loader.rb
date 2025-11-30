# frozen_string_literal: true

require "csv"

module Broadlistening
  # Loads comments from CSV files with Kouchou-AI compatible format.
  #
  # This loader supports the CSV format used by Kouchou-AI (Python version),
  # enabling compatibility testing between the two implementations.
  #
  # @example Loading a Kouchou-AI format CSV
  #   comments = CsvLoader.load("inputs/example-polis.csv")
  #
  # @example Loading with property columns
  #   comments = CsvLoader.load("data.csv", property_names: ["agrees", "disagrees"])
  #
  # @example Using custom column mapping
  #   comments = CsvLoader.load("custom.csv", column_mapping: {
  #     id: "my_id_column",
  #     body: "my_body_column"
  #   })
  class CsvLoader
    # Default column mapping for Kouchou-AI format
    # Maps Ruby gem's expected keys to Kouchou-AI's CSV column names
    KOUCHOU_AI_COLUMNS = {
      id: "comment-id",
      body: "comment-body",
      source_url: "source-url"
    }.freeze

    class << self
      # Load comments from a CSV file
      #
      # @param path [String] Path to the CSV file
      # @param property_names [Array<String>] Property column names to extract
      # @param column_mapping [Hash] Custom column name mapping (overrides defaults)
      # @param encoding [String] File encoding (default: UTF-8 with BOM handling)
      # @return [Array<Comment>] Array of Comment objects
      def load(path, property_names: [], column_mapping: {}, encoding: "bom|utf-8")
        mapping = KOUCHOU_AI_COLUMNS.merge(column_mapping)

        comments = []
        CSV.foreach(path, headers: true, encoding: encoding) do |row|
          comment = build_comment(row, mapping, property_names)
          comments << comment unless comment.nil?
        end
        comments
      end

      # Load comments from a CSV string
      #
      # @param csv_string [String] CSV content as string
      # @param property_names [Array<String>] Property column names to extract
      # @param column_mapping [Hash] Custom column name mapping
      # @return [Array<Comment>] Array of Comment objects
      def parse(csv_string, property_names: [], column_mapping: {})
        mapping = KOUCHOU_AI_COLUMNS.merge(column_mapping)

        comments = []
        CSV.parse(csv_string, headers: true) do |row|
          comment = build_comment(row, mapping, property_names)
          comments << comment unless comment.nil?
        end
        comments
      end

      private

      def build_comment(row, mapping, property_names)
        id = extract_value(row, mapping[:id], "id")
        body = extract_value(row, mapping[:body], "body")

        # Skip rows without required fields
        return nil if id.nil? || body.nil? || body.strip.empty?

        hash = {
          id: id.to_s,
          body: body,
          source_url: extract_value(row, mapping[:source_url], "source_url", "source-url")
        }

        # Extract attribute columns (attribute_* or attribute-*)
        row.headers.each do |header|
          next if header.nil?

          if header.start_with?("attribute_") || header.start_with?("attribute-")
            hash[header.to_sym] = row[header]
          end
        end

        # Extract property columns
        property_names.each do |prop_name|
          value = row[prop_name] || row[prop_name.to_s.tr("_", "-")]
          hash[prop_name.to_sym] = value if value
        end

        Comment.from_hash(hash, property_names: property_names)
      end

      def extract_value(row, *possible_names)
        possible_names.compact.each do |name|
          value = row[name]
          return value unless value.nil?
        end
        nil
      end
    end
  end
end
