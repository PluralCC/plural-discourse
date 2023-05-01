# frozen_string_literal: true

class VoiceCreditsController < ApplicationController
  requires_login except: [:total_votes_per_topic_for_category]

  def index
    category_id = params.require(:category_id)
    if category_id == "all"
      voice_credits = VoiceCredit.where(user_id: current_user.id).includes(:topic, :category)
    else
      voice_credits =
        VoiceCredit.where(user_id: current_user.id, category_id: category_id).includes(
          :topic,
          :category,
        )
    end
    voice_credits_by_topic_id = voice_credits.index_by(&:topic_id)

    render json: {
             success: true,
             voice_credits_by_topic_id: voice_credits_by_topic_id,
             voice_credits:
               ActiveModel::ArraySerializer.new(
                 voice_credits,
                 each_serializer: VoiceCreditSerializer,
               ),
           }
  end

  # Returns the total vote value per topic for a given category
  # The vote value is the translation of voice_credits (SQRT(voice_credits)
  def total_votes_per_topic_for_category
    category_id = params[:category_id]
    voice_credit_totals =
      VoiceCredit
        .where(category_id: category_id)
        .map { |record| { topic_id: record.topic_id, vote_value: record.vote_value } }

    result = {}
    discounted_result = {}

    ### get Totals with correlation discount
    unique_users = User.all
    unique_groups =
      UserFieldOption.all.map { |x| "user_field_#{x.user_field_id}_#{x.value}".gsub(/\s+/, "_") }
    unique_groups << "no_group"

    unique_topics = Topic.where(category_id: category_id)
    custom_fields = UserCustomField.all

    user_groups =
      custom_fields
        .group_by(&:user_id)
        .map do |user_id, fields|
          formatted_fields = fields.map { |x| "#{x.name}_#{x.value}" }
          { user_id: user_id, groups: formatted_fields }
        end
    # we need to add the users that have no custom fields
    group_user_ids = user_groups.map { |x| x[:user_id] }
    no_group_users_ids = unique_users.filter { |x| !group_user_ids.include?(x.id) }.map(&:id)
    no_group_users_ids.each { |user_id| user_groups << { user_id: user_id, groups: ["no_group"] } }

    user_votes = VoiceCredit.where("credits_allocated > 0 AND category_id = ?", category_id)

    processed_groups, topic_contributions =
      ClusterMatchQvHelper.process_data(
        unique_users,
        unique_groups,
        unique_topics,
        user_groups,
        user_votes,
      )

    ## TODO both loops can be merged into one
    voice_credit_totals.each do |ct|
      topic_id = ct[:topic_id]
      vote_value = topic_contributions[topic_id]

      if vote_value.nil?
        discounted_result[topic_id] = { topic_id: topic_id, total_votes: 0 }
      else
        puts "topic_id: #{topic_id}"
        value_score = ClusterMatchQvHelper.cluster_match(processed_groups, vote_value)
        discounted_result[topic_id] = { topic_id: topic_id, total_votes: value_score }
      end
    end
    # topic_contributions example
    # {3=>[6, 0, 0, 0, 0, 0], 29=>[13, 0, 0, 0, 0, 0], 34=>[10, 0, 1, 0, 0, 0], 44=>[17, 0, 0, 0, 0, 0], 39=>[49, 0, 0, 0, 0, 0]}

    voice_credit_totals.each do |ct|
      topic_id = ct[:topic_id]
      vote_value = ct[:vote_value]
      if result[topic_id].nil?
        result[topic_id] = { topic_id: topic_id, total_votes: vote_value }
      else
        result[topic_id][:total_votes] += vote_value
      end
    end

    # Square the sum of total votes per topic
    result.each { |topic_id, topic_data| topic_data[:total_votes] = topic_data[:total_votes]**2 }

    render json: {
             success: true,
             total_vote_values_per_topic: result,
             discounted_total_vote_values_per_topic: discounted_result,
           }
  end

  def create
    category_id = params["category_id"]
    user_id = current_user.id
    voice_credits_data = params.require("voice_credits_data").values()
    if voice_credits_data.empty?
      render json: { success: false, error: "Credits missing." }, status: :unprocessable_entity
      return
    end
    voice_credits_data.each do |v_c|
      if v_c["topic_id"].nil? || v_c["credits_allocated"].nil?
        render json: {
                 success: false,
                 error: "Missing attributes for voice credit.",
               },
               status: :unprocessable_entity
        return
      end
    end

    if voice_credits_data.map { |vc| vc[:credits_allocated].to_i }.sum > 100
      render json: {
               success: false,
               error: "Credits allocation exceeded the limit of 100.",
             },
             status: :unprocessable_entity
      return
    end

    VoiceCredit.transaction do
      voice_credits_data.each do |voice_credit|
        VoiceCredit.find_or_initialize_by(
          user_id: user_id,
          topic_id: voice_credit[:topic_id].to_i,
          category_id: category_id.to_i,
        ).update!(credits_allocated: voice_credit[:credits_allocated].to_i)
      end
    end
    render json: { success: true }
  end
end
