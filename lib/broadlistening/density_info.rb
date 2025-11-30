# frozen_string_literal: true

module Broadlistening
  # Represents density information for a cluster.
  #
  # DensityInfo is an immutable value object that holds the calculated
  # density metrics for a cluster, including rank percentile within its level.
  #
  # @example Creating density info
  #   info = DensityInfo.new(
  #     density: 0.85,
  #     density_rank: 3,
  #     density_rank_percentile: 0.25
  #   )
  DensityInfo = Data.define(:density, :density_rank, :density_rank_percentile) do
    # Convert to hash for serialization
    #
    # @return [Hash{Symbol => Float | Integer}]
    def to_h
      {
        density: density,
        density_rank: density_rank,
        density_rank_percentile: density_rank_percentile
      }
    end
  end
end
