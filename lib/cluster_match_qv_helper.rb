# frozen_string_literal: true

module ClusterMatchQvHelper
  # mirrors https://github.com/erichfi/connection-oriented-quadratic/blob/main/QV.rb
  # groups - an array of arrays of user indices that are part of the same group
  def self.cluster_match(groups, contributions)
    group_memberships_map = Array.new(contributions.length) { [] }

    groups.each_with_index { |group, i| group.each { |j| group_memberships_map[j] << i } }
    ## group_memberships_map  group_memberships_map: [[2, 3], [], [], [], [2], []]

    common_group =
      lambda do |i, j|
        group_memberships_map[i].any? { |group| group_memberships_map[j].include?(group) }
      end

    k =
      lambda do |i, group|
        if group.include?(i) || group.any? { |j| common_group.call(i, j) }
          Math.sqrt(contributions[i])
        else
          contributions[i]
        end
      end

    result = 0

    groups.each { |g| g.each { |i| result += contributions[i] / group_memberships_map[i].length } }
    groups.each do |g|
      groups.each do |h|
        next if g == h

        term1 = 0
        g.each { |i| term1 += k.call(i, h) / group_memberships_map[i].length }
        term1 = Math.sqrt(term1)

        term2 = 0
        h.each { |j| term2 += k.call(j, g) / group_memberships_map[j].length }
        term2 = Math.sqrt(term2)

        result += term1 * term2
      end
    end
    Math.sqrt(result)
  end

  ## unique_users: list of user Objects from User Model
  ## unique_groups: list of group names. EX: ["user_field_1_Ethereum_Foundation", "user_field_1_Radical_Exchange", "user_field_1_Other", "user_field_2_Asia", "user_field_2_Europe", "no_group"]
  ## unique_topics: list of topic Objects from Topic Model
  ## user_groups: [{:user_id=>1, :groups=>["user_field_1_Other", "user_field_2_Asia"]},{:user_id=>-2, :groups=>["no_group"]... ]
  ## user_votes: list of Voice credit objects from VoiceCredit Model
  def self.process_data(unique_users, unique_groups, unique_topics, user_groups, user_votes)
    # Create a mapping of user_id to the index
    user_index_mapping = {}
    unique_users.each_with_index { |user, index| user_index_mapping[user.id] = index }
    # Create a mapping of group to the index
    group_index_mapping = {}
    unique_groups.each_with_index { |group, index| group_index_mapping[group] = index }

    # Process user_groups to match the format required by cluster_match
    processed_groups = Array.new(unique_groups.length) { [] }
    user_groups.each do |user_group|
      user_index = user_index_mapping[user_group[:user_id]]
      next unless user_index
      user_group[:groups].each do |group|
        group_index = group_index_mapping[group]
        next unless group_index

        processed_groups[group_index] << user_index
      end
    end

    # Process user_votes to get contributions per topic
    topic_contributions = Hash.new { |h, k| h[k] = Array.new(unique_users.length, 0) }
    user_votes.each do |contribution|
      user_index = user_index_mapping[contribution[:user_id]]
      next unless user_index

      topic_id = contribution[:topic_id]
      topic_contributions[topic_id][user_index] += contribution[:credits_allocated]
    end

    ## topic contr: {3=>[6, 0, 0, 0, 0, 0], 29=>[13, 0, 0, 0, 0, 0], 34=>[10, 0, 1, 0, 0, 0], 44=>[17, 0, 0, 0, 0, 0], 39=>[49, 0, 0, 0, 0, 0]}
    [processed_groups, topic_contributions]
  end

  ## unique_users: list of user Objects from User Model
  ## unique_groups: list of group names. EX: ["user_field_1_Ethereum_Foundation", "user_field_1_Radical_Exchange", "user_field_1_Other", "user_field_2_Asia", "user_field_2_Europe", "no_group"]
  ## unique_topics: list of topic Objects from Topic Model
  ## user_groups: [{:user_id=>1, :groups=>["user_field_1_Other", "user_field_2_Asia"]},{:user_id=>-2, :groups=>["no_group"]... ]
  ## user_votes: list of Voice credit objects from VoiceCredit Model
  def self.sort_by_topics_score(unique_users, unique_groups, unique_topics, user_groups, user_votes)
    processed_groups, topic_contributions =
      process_data(unique_users, unique_groups, unique_topics, user_groups, user_votes)

    sorted_unique_topics =
      unique_topics.sort_by do |topic|
        topic_id = topic[:id] # Replace 'topic_id' with the appropriate attribute/method name
        contributions = topic_contributions[topic_id]
        topic_score = cluster_match(processed_groups, contributions)
        -topic_score
      end

    ids = sorted_unique_topics.map(&:id)
    aa_sorted_unique_topics =
      unique_topics.where(id: ids).order(
        "ARRAY_POSITION(ARRAY[#{ids.join(",")}], #{unique_topics.table_name}.id)",
      )

    aa_sorted_unique_topics
  end
end
