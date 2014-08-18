#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'bundler/setup'

require_relative 'text_processor'
require_relative 'twitter_wrapper'

class KingOfGakugeeeekaiBot

	def initialize(debug)
		STDOUT.sync = true
		
		@debug = debug
		@logger = Logger.new(STDOUT)
		@processor = TextProcessor.new(@logger, @debug)
		@twitter = TwitterWrapper.new(@logger, @debug, @processor)
	end

	# running KingOfGakugeeeekai!
	def run
		@logger.info("ohayoooooo!!")
		@twitter.tweet_update(@processor.wakeup_message(Time.now))

		@logger.info("[stream] start!")

		timelines = @twitter.timeline(false)
		@logger.info("[tweet] first: get home timeline!!! : #{timelines.length}")
		@logger.info("[tweet] first: save tweets start -----")
		@processor.save_tweet_text(timelines)
		@logger.info("[tweet] first: save tweets end : size is #{@processor.get_markov_table.length} -----")

		begin
			EM.run do
				# auto follow and unfollow
				EM.add_periodic_timer(3600) do
					@twitter.friends_management()
				end

				# tweet
				EM.add_periodic_timer(1800) do
					@twitter.tweet_update(@processor.generate_tweet(true))
				end

				# tweet文章のリフレッシュ
				EM.add_periodic_timer(3600) do
					timelines = @twitter.timeline(false)
					@logger.info("[tweet] get home timeline!!!: #{timelines.length}")
					@logger.info("[tweet] save tweets start -----")
					@processor.save_tweet_text(timelines)
					@logger.info("[tweet] save tweets end : size is #{@processor.get_markov_table.length} -----")
				end

				# タイムラインが更新された時
				@twitter.userstream do |status|
					@logger.info("[stream] tweet reply?: #{status.in_reply_to_screen_name}")

					if @twitter.reply_me?(status)
						# 自分へのリプライのみ返信
						tweet = @processor.reply(status.user.screen_name, status.text)
						next if tweet.nil?

						EM.add_timer(rand(8) + 5) do
							@twitter.tweet_update(tweet, status.id)
						end		
					else
						next if @twitter.exclude_tweet?(status)
					end
				end
			end
		rescue => e
			@logger.error("[stream] message=#{e.message}, class=#{e.class}, backtrace=#{e.backtrace}")
			retry
		end

	end

	def self.ohayo(debug = false)
		self.new(debug).run
	end
end

# debug指定の場合はtrue
debug = ARGV.any? { |arg| %w(-d --debug).include?(arg) }

# king of gakugeeeekai bot start!
KingOfGakugeeeekaiBot.ohayo(debug)