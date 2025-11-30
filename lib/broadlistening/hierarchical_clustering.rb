# frozen_string_literal: true

module Broadlistening
  class HierarchicalClustering
    # Ward法による階層的クラスタリング
    # scipy.cluster.hierarchy.linkage(method="ward") と同等の実装

    class << self
      def merge(centroids, labels, target_clusters)
        new(centroids, labels, target_clusters).merge
      end
    end

    def initialize(centroids, labels, target_clusters)
      @centroids = to_numo_array(centroids)
      @labels = labels.dup
      @target_clusters = target_clusters
      @n_original_clusters = @centroids.shape[0]
    end

    def merge
      return @labels if current_cluster_count <= @target_clusters

      # クラスタ情報を初期化
      # 各クラスタ: {centroid: 重心, size: サイズ, members: 元のクラスタID}
      clusters = initialize_clusters

      # Ward法で階層的にマージ
      while clusters.size > @target_clusters
        c1_id, c2_id = find_ward_closest_pair(clusters)
        break if c1_id.nil?

        merge_ward_clusters!(clusters, c1_id, c2_id)
      end

      # 元のラベルを新しいクラスタIDにマッピング
      build_final_labels(clusters)
    end

    private

    def to_numo_array(centroids)
      if centroids.is_a?(Numo::DFloat)
        centroids
      else
        Numo::DFloat.cast(centroids)
      end
    end

    def current_cluster_count
      @labels.uniq.size
    end

    def initialize_clusters
      clusters = {}
      @n_original_clusters.times do |i|
        clusters[i] = ClusterInfo.new(
          centroid: @centroids[i, true].to_a,
          size: @labels.count(i),
          members: [ i ]
        )
      end
      clusters
    end

    def find_ward_closest_pair(clusters)
      min_dist = Float::INFINITY
      min_pair = [ nil, nil ]

      cluster_ids = clusters.keys
      cluster_ids.each_with_index do |c1_id, i|
        cluster_ids[(i + 1)..].each do |c2_id|
          dist = clusters[c1_id].ward_distance_to(clusters[c2_id])
          if dist < min_dist
            min_dist = dist
            min_pair = [ c1_id, c2_id ]
          end
        end
      end

      min_pair
    end

    def merge_ward_clusters!(clusters, c1_id, c2_id)
      c1 = clusters[c1_id]
      c2 = clusters[c2_id]

      # マージしたクラスタを作成（小さいIDを使用）
      merged_id = [ c1_id, c2_id ].min
      removed_id = [ c1_id, c2_id ].max

      clusters[merged_id] = c1.merge_with(c2)
      clusters.delete(removed_id)
    end

    def build_final_labels(clusters)
      # 各元クラスタIDから最終クラスタIDへのマッピングを構築
      original_to_final = {}
      clusters.each_value do |cluster|
        final_id = cluster.min_member
        cluster.members.each do |original_id|
          original_to_final[original_id] = final_id
        end
      end

      # 連番に振り直し
      unique_finals = original_to_final.values.uniq.sort
      final_remap = unique_finals.each_with_index.to_h

      @labels.map { |l| final_remap[original_to_final[l]] }
    end
  end
end
