# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Broadlistening::CsvLoader do
  describe ".load" do
    context "with Kouchou-AI format CSV" do
      let(:csv_content) do
        <<~CSV
          timestamp,comment-id,author-id,agrees,disagrees,comment-body
          1695309375466,321,210,3,1,"AI should be in line with democratic principles."
          1695372499305,341,197,6,0,"Public awareness about AI needs to be improved."
          1695372492070,340,197,5,0,"The benefits of AI should be equitably distributed."
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "loads comments from Kouchou-AI format CSV" do
        comments = described_class.load(csv_file.path)

        expect(comments.size).to eq(3)
        expect(comments.first).to be_a(Broadlistening::Comment)
      end

      it "maps comment-id to id" do
        comments = described_class.load(csv_file.path)

        expect(comments.first.id).to eq("321")
        expect(comments.last.id).to eq("340")
      end

      it "maps comment-body to body" do
        comments = described_class.load(csv_file.path)

        expect(comments.first.body).to eq("AI should be in line with democratic principles.")
      end

      it "extracts property columns when specified" do
        comments = described_class.load(csv_file.path, property_names: [ "agrees", "disagrees" ])

        expect(comments.first.properties).to eq({
          "agrees" => "3",
          "disagrees" => "1"
        })
      end
    end

    context "with attribute columns" do
      let(:csv_content) do
        <<~CSV
          comment-id,comment-body,attribute_age,attribute_region
          1,"Test comment","30s","Tokyo"
          2,"Another comment","40s","Osaka"
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "extracts attribute_* columns" do
        comments = described_class.load(csv_file.path)

        expect(comments.first.attributes).to eq({
          "age" => "30s",
          "region" => "Tokyo"
        })
      end
    end

    context "with hyphenated attribute columns" do
      let(:csv_content) do
        <<~CSV
          comment-id,comment-body,attribute-age,attribute-region
          1,"Test comment","30s","Tokyo"
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "extracts attribute-* columns" do
        comments = described_class.load(csv_file.path)

        expect(comments.first.attributes).to eq({
          "age" => "30s",
          "region" => "Tokyo"
        })
      end
    end

    context "with custom column mapping" do
      let(:csv_content) do
        <<~CSV
          my_id,my_body,my_url
          1,"Custom format comment","https://example.com/1"
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "uses custom column mapping" do
        comments = described_class.load(
          csv_file.path,
          column_mapping: {
            id: "my_id",
            body: "my_body",
            source_url: "my_url"
          }
        )

        expect(comments.first.id).to eq("1")
        expect(comments.first.body).to eq("Custom format comment")
        expect(comments.first.source_url).to eq("https://example.com/1")
      end
    end

    context "with source-url column" do
      let(:csv_content) do
        <<~CSV
          comment-id,comment-body,source-url
          1,"Test comment","https://example.com/comment/1"
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "extracts source-url" do
        comments = described_class.load(csv_file.path)

        expect(comments.first.source_url).to eq("https://example.com/comment/1")
      end
    end

    context "with empty rows" do
      let(:csv_content) do
        <<~CSV
          comment-id,comment-body
          1,"Valid comment"
          2,""
          3,"   "
          4,"Another valid comment"
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "skips rows with empty body" do
        comments = described_class.load(csv_file.path)

        expect(comments.size).to eq(2)
        expect(comments.map(&:id)).to eq([ "1", "4" ])
      end
    end

    context "with missing required columns" do
      let(:csv_content) do
        <<~CSV
          comment-id,comment-body
          ,""
          ,"Some body"
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ "test", ".csv" ])
        file.write(csv_content)
        file.close
        file
      end

      after { csv_file.unlink }

      it "skips rows without id or body" do
        comments = described_class.load(csv_file.path)

        expect(comments).to be_empty
      end
    end
  end

  describe ".parse" do
    let(:csv_string) do
      <<~CSV
        comment-id,comment-body
        1,"First comment"
        2,"Second comment"
      CSV
    end

    it "parses CSV string" do
      comments = described_class.parse(csv_string)

      expect(comments.size).to eq(2)
      expect(comments.first.id).to eq("1")
      expect(comments.first.body).to eq("First comment")
    end

    it "accepts property_names" do
      csv_with_props = <<~CSV
        comment-id,comment-body,score
        1,"Test",10
      CSV

      comments = described_class.parse(csv_with_props, property_names: [ "score" ])

      expect(comments.first.properties).to eq({ "score" => "10" })
    end
  end

  describe "KOUCHOU_AI_COLUMNS constant" do
    it "defines standard Kouchou-AI column mappings" do
      expect(described_class::KOUCHOU_AI_COLUMNS).to eq({
        id: "comment-id",
        body: "comment-body",
        source_url: "source-url"
      })
    end
  end
end
