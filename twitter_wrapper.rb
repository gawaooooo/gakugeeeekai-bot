#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'twitter'
require 'tweetstream'

class TwitterWrapper
	attr_reader :client, :stream

	TIMELINE_GET_COUNT = 200

	# @param [Logger] Logger instance
	# @param [Boolean] debug trueの場合デバッグモード
	# @param [TextProcessor] processor TextProcessor instance
	def initialize(logger, debug = false, processor)
		@debug = debug
		@logger = logger
		@processor = processor
		@client = Twitter::REST::Client.new do |config|
			config.consumer_key = ENV['TWITTER_CONSUMER_KEY'] # API Key
			config.consumer_secret = ENV['TWITTER_CONSUMER_SECRET'] # API secret
			config.access_token = ENV['TWITTER_ACCESS_TOKEN'] # Access token
			config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET'] # Access token secret
		end
		@profile = @client.verify_credentials

		TweetStream.configure do |config|
			config.consumer_key       = ENV['TWITTER_CONSUMER_KEY']
			config.consumer_secret    = ENV['TWITTER_CONSUMER_SECRET']
			config.oauth_token        = ENV['TWITTER_ACCESS_TOKEN']
			config.oauth_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
			config.auth_method        = :oauth
		end

		@stream = TweetStream::Client.new

		EM.error_handler do |e|
			@logger.error("[client] #{e.message}")
		end

		@stream.on_inited do
			@logger.info("[client] inited")
		end
	end

	def userstream(&block)
		@logger.info("[stream] call userstream")
		@stream.userstream(&block)
	end


	def direct_message(&block)
		@stream.on_direct_message(&block)
	end

	def timeline_status(&block)
		@stream.on_timeline_status(&block)
	end


	# home timelineから最新のN件取得
	# @param [Boolean] join trueの場合、配列を結合して文字列として返す
	# @return [Array/String] 取得したタイムライン
	def timeline(join = false)
		timelines = []
		max_id = 0
		# 最初の200件取得
		@client.home_timeline(:count => TIMELINE_GET_COUNT).each do |tweet|
			# @logger.debug("[tweet] #{tweet.text}")
			text = @processor.formatting(tweet.text)
			# @logger.debug("[tweet] after #{text}")
			next if text.empty?
			timelines.push text
			max_id = tweet.id - 1
		end

		# 残り400件取得
		2.times {
			@client.home_timeline(:count => TIMELINE_GET_COUNT,:max_id => max_id).each do |tweet|
				# @logger.debug("[tweet] #{tweet.text}")
				text = @processor.formatting(tweet.text)
				# @logger.debug("[tweet] after #{text}")
				next if text.empty?
				timelines.push text
				max_id = tweet.id - 1
			end
		}

		if join
			timelines = timelines.join('。')
		end
		return timelines
	end

	# follow
	# @param [Fixnum] id user id
	def follow(id)
		@logger.info("[client] follow %s" % id)
		return nil if @debug
		if @client.follow(id)
			@logger.info("[client] done.")
		end
	end

	# unfollow
	# @param [Fixnum] id user id
	def unfollow(id)
		@logger.info("[client] unfollow %s" % id)
		return nil if @debug
		if @client.unfollow(id)
			@logger.info("[client] done.")
		end
	end

	# tweet update!
	# @param [String] message tweet message
	# @id [Fixnum] id reply user id
	def tweet_update(message, id = nil)
		option = {}
		option[:in_reply_to_status_id] = id if id
		if @debug
			@logger.debug("[client] Tweeted:#{message}, Option:#{option}")
		else
			tweet = @client.update(message, option)
			if tweet
				@logger.info("[client] tweeted: %s" % tweet.text)
			end
		end
	end

	# friends management
	# follow, unfollow
	def friends_management
		friends = @client.friend_ids.to_a
		followers = @client.follower_ids.to_a

		to_follow = followers - friends
		# to_unfollow = friends - followers

		to_follow.each do |id|
			follow(id)
		end

		# 一旦停止 
		# to_unfollow.each do |id|
		# 	unfollow(id)
		# end
	end

	# user id is me?
	# @param [Fixnum] id user id
	# @return [Boolean] true is me!
	def me?(id)
		id == @profile.id
	end

	# reply me?
	# @param status object
	# @return [Boolean] true is reply me
	def reply_me?(status)
		return true if ((status.in_reply_to_screen_name == @profile.screen_name) and (not me?(status.user.id)))
	end

	# exclude tweet
	# @param status object
	# @return [Boolean] true is exclude status
	def exclude_tweet?(status)
		return true if me?(status.user.id)
		return true if status.retweeted?
		return true unless status.in_reply_to_screen_name.nil?
		return false
	end
end