#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'pathname'
require 'yaml'
require 'yahoo_parse_api'

class TextProcessor

	# data directory
	DATA_DIR = Pathname.new(__FILE__).dirname.join('data')

	BEGIN_FLG = '[BEGIN]'
	END_FLG = '[END]'
	
	HASH_TAG = ' #ebichu #エビ中'

	# Read for yaml files.
	# ready YahooParseApi.
	# @param [Logger] Logger instance
	# @param [Boolean] debug trueの場合デバッグモード
	def initialize(logger, debug)
		@logger = logger
		@debug = debug

		@face = YAML.load(DATA_DIR.join('face.yaml').read)
		@student = YAML.load(DATA_DIR.join('student.yaml').read)
		# @report = YAML.load(DATA_DIR.join('report.yaml').read)
		@song = YAML.load(DATA_DIR.join('song.yaml').read)

		# YahooParseApiのインスタンス生成
		# @see https://github.com/kyohei8/yahoo_parse_api
		YahooParseApi::Config.app_id = ENV['YAHOO_APP_ID']
		@parse_api = YahooParseApi::Parse.new
	end

	# Wakeup kingofgakugeeeekai_bot
	# @param [Time] time wakeup time
	# @return [String] wake up message
	def wakeup_message(time)
		formated_time = time.strftime('%Y年%m月%d日 %H時%M分%S秒')
		"#{formated_time} 朝のチャイムが鳴りました！私たち、私立恵比寿中学好きなキングオブ学芸会botです！ <゜))))彡"
	end

	# @deprecated
	# Call to user for message
	# @param [String] user_name tweet for @user_name
	# @param [String] text original message
	# @return [String] message
	# @return [nil] not to do.
	# def call_to_user(user_name, text)
	# 	tweet = report(text)
	# 	return nil if tweet.nil?

	# 	"@#{user_name} #{tweet} by#{student} #{face}"
	# end

	# @deprecated
	# Report
	# @param [String] text tweet text.
	# @return [String] reply string
	# @return [nil] not reply
	# def report(text)
	# 	@report.each do |match_word|
	# 		match_word["word"].each do |word|
	# 			return match_word["response"] if text =~ /#{word}/
	# 		end
	# 	end

	# 	nil
	# end

	# テキスト内にメンバー名が含まれている場合は出席番号を返す
	# @param [String] text tweet text.
	# @return [Number] id
	# @return [nil] not
	def student(text)
		return nil if text.nil?

		@student.each do |s|
			s['name'].each do |n|
				return s['number'] if text =~ /#{n}/
			end
		end

		nil
	end

	# Face mark
	# @param [Fixnum] number 出席番号
	# @return [String] 顔文字
	# @return [nil] 顔文字がない
	def face(number)
		face = nil
		@face.each do |f|
			if number == f['number']
				face = f['face']	
				break
			end
		end

		@logger.debug("[face] number: #{number} / #{face}") if @debug
		return nil if face.nil?
		face.sample
	end

	# Song
	# @return [Array] 歌詞の一部
	def song
		@song.sample(40)
	end

	# いらない文字列除去
	# @param [String] text 整形する文字列
	# @return [String] 整形済み文字列
	# @return [nil] 整形文字列がない
	def formatting(text)
		return nil if text.nil?
		text = text.gsub(/(\n|\r\n)/, '') # 改行コードを置換
		text = text.gsub(/(RT|QT)\s*@?[0-9A-Za-z_]+.*$/, '')	# RT/QT以降行末まで削除 
		text = text.gsub(/\.?\s*@[0-9A-Za-z_]+/, '')	# リプライをすべて削除
		text = text.gsub(/htt(p|ps):\/\/\S+/, '')	# URLを削除 スペースが入るまで消える
		text = text.gsub(/#(?:\p{Hiragana}|\p{Katakana}|[ー－]|[一-龠々]|[0-9A-Za-z_])+/, '')	# ハッシュタグを削除
		text = text.strip
		return text
	end

	# ランダムにつぶやく文字列を保持
	# @param [Array] timelines 取得したタイムライン
	def save_tweet_text(timelines)
		lyric = song()
		@tweets = timelines + lyric
		make_markov_table()
	end

	# 形態素解析する(分割) して配列に保持しておく
	# @see https://github.com/takuti/twitter-bot/blob/master/markov.rb
	def make_markov_table
		# 3階のマルコフ連鎖	
		@markov_table = Array.new
		markov_index = 0

		@tweets.each do |tweet|
			tweet = tweet.to_s

			wakati_array = Array.new
			wakati_array << BEGIN_FLG

			# Yahoo形態素解析APIを使用	
			result = @parse_api.parse(tweet, { results: 'ma,uniq', uniq_filter: '9|10' }, :POST)
			word_list = result['ResultSet']['ma_result']['word_list']['word']
			tmp_word_list = Array.new
			unless word_list.kind_of?(Array) then
				tmp_word_list.push word_list
			else
				tmp_word_list = word_list
			end

			surface_array = Array.new
			tmp_word_list.each do |w|
				surface_array.push w['surface']
			end

			wakati_array += surface_array
			wakati_array << END_FLG

			# 要素は最低4つあれば[BEGIN]で始まるものと[END]で終わるものの2つが作れる
			next if wakati_array.size < 4
			i = 0
			loop do
				@markov_table[markov_index] = Array.new
				@markov_table[markov_index] << wakati_array[i]
				@markov_table[markov_index] << wakati_array[i + 1]
				@markov_table[markov_index] << wakati_array[i + 2]
				markov_index += 1
				break if wakati_array[i + 2] == END_FLG
				i += 1
			end
		end
	end

	# reply
	# @param [String] user_name tweet for @user_name
	# @param [String] text original message
	# @return [String] message
	# @return [nil] not to do.
	def reply(user_name, text)
		number = student(text)
		tweet = generate_tweet(false, number)
		return nil if tweet.nil?

		"@#{user_name} #{tweet}"
	end

	# つぶやきを作る
	# @see https://github.com/takuti/twitter-bot/blob/master/markov.rb
	# @param [Boolean] hashtag trueの場合は定義されているハッシュタグを付与
	# @param [Fixnum] number 出席番号またはnil
	# @return [String] markov_tweet つぶやく文字列	
	def generate_tweet(hashtag = false, number = nil)
		while true
			# 先頭（[BEGIN]から始まるもの）を選択
			selected_array = Array.new
			@markov_table.each do |markov_array|
				if markov_array[0] == BEGIN_FLG
					selected_array << markov_array
				end
			end
			selected = selected_array.sample
			markov_tweet = selected[1] + selected[2]
			# 以後、[END]で終わるものを拾うまで連鎖を続ける
			loop do

				if markov_tweet.size > 110
					break
				end

				selected_array = Array.new
				@markov_table.each do |markov_array|
					if markov_array[0] == selected[2]
						selected_array << markov_array
					end
				end
				break if selected_array.size == 0 # 連鎖出来なければあきらめる
				selected = selected_array.sample
				if selected[2] == END_FLG
					markov_tweet += selected[1]
					break
				else
					markov_tweet += selected[1] + selected[2]
				end
			end

			break
		end

		# 文字数が少なかったら顔文字を入れる
		if markov_tweet.size <= 100
			# number = student(markov_tweet)
			number = student(markov_tweet) if number.nil?
			unless number.nil?
				# 生徒の名前が入っていたら対応する顔文字を取得
				face = face(number)
				unless face.nil?
					# 顔文字があったら追加
					markov_tweet += face
				end
			end
		end

		if hashtag
			markov_tweet += HASH_TAG
		end

		markov_tweet
	end

	# 保存したmarkov_tableを返す
	# @return @markov_table
	def get_markov_table
		@markov_table
	end
end