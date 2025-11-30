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
        clusters[i] = {
          centroid: @centroids[i, true].to_a,
          size: @labels.count(i),
          members: [ i ]
        }
      end
      clusters
    end

    def find_ward_closest_pair(clusters)
      min_dist = Float::INFINITY
      min_pair = [ nil, nil ]

      cluster_ids = clusters.keys
      cluster_ids.each_with_index do |c1_id, i|
        cluster_ids[(i + 1)..].each do |c2_id|
          dist = ward_distance(clusters[c1_id], clusters[c2_id])
          if dist < min_dist
            min_dist = dist
            min_pair = [ c1_id, c2_id ]
          end
        end
      end

      min_pair
    end

    def ward_distance(cluster1, cluster2)
      # Ward法: マージ時の分散増加量を計算
      # d(i,j) = sqrt(2 * n_i * n_j / (n_i + n_j)) * ||c_i - c_j||
      n1 = cluster1[:size]
      n2 = cluster2[:size]
      c1 = cluster1[:centroid]
      c2 = cluster2[:centroid]

      # ユークリッド距離の2乗
      dist_sq = c1.zip(c2).sum { |a, b| (a - b)**2 }

      # Ward距離
      Math.sqrt(2.0 * n1 * n2 / (n1 + n2) * dist_sq)
    end

    def merge_ward_clusters!(clusters, c1_id, c2_id)
      c1 = clusters[c1_id]
      c2 = clusters[c2_id]

      # 新しい重心を計算（サイズで重み付け）
      n1 = c1[:size]
      n2 = c2[:size]
      new_size = n1 + n2

      new_centroid = c1[:centroid].zip(c2[:centroid]).map do |v1, v2|
        (v1 * n1 + v2 * n2) / new_size
      end

      # マージしたクラスタを作成（小さいIDを使用）
      merged_id = [ c1_id, c2_id ].min
      removed_id = [ c1_id, c2_id ].max

      clusters[merged_id] = {
        centroid: new_centroid,
        size: new_size,
        members: c1[:members] + c2[:members]
      }

      clusters.delete(removed_id)
    end

    def build_final_labels(clusters)
      # 各元クラスタIDから最終クラスタIDへのマッピングを構築
      original_to_final = {}
      clusters.each_value do |cluster|
        final_id = cluster[:members].min
        cluster[:members].each do |original_id|
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
