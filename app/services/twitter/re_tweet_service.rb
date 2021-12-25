require 'rubygems'
require 'bundler/setup'

require 'twitter'
require 'figaro'

Figaro.application = Figaro::Application.new(
  environment: 'production',
  path: File.expand_path('config/application.yml')
)

Figaro.load

module Twitter
  class ReTweetService
    attr_reader :config

    HASHTAGS_TO_WATCH = %w[#rails #ruby #RubyOnRails]

    # Rest Client, rest client provides endpoints to perform one time 
    # operations like tweet, retweet, like, etc.

    # Stream Client, stream client streams all tweets in real 
    # time and watches the hashtags

    def initialize
      @config = twitter_api_config
    end

    def perform
      rest_client = configure_rest_client
      stream_client = configure_stream_client

      # using while true so that services runs forever, once started.
      while true
        puts 'Starting to retweet 3, 2, 1...NOW!'

        re_tweet(rest_client, stream_client)
      end
    end

    private

    MAXIMUM_HASHTAG_COUNT = 10

    def hashtags(tweet)
      tweet_hash = tweet.to_h
      extended_tweet = tweet_hash[:extended_tweet]

      (extended_tweet && extended_tweet[:entities][:hashtags]) ||
      tweet_hash[:entities][:hashtags]
    end

    # Check if received tweet is an original tweet or retweeted one, 
    # if it was retweeted then this method returns false and bot doesn’t retweet.
    def tweet?(tweet)
      tweet.is_a?(Twitter::Tweet)
    end

    # Check if received tweet is not original and just retweeted, 
    # bot will skip this tweet if this method return true
    def retweet?(tweet)
      tweet.retweet?
    end

    def allowed_hashtags?(tweet)
      includes_allowed_hashtags = false

      hashtags(tweet).each do |hashtag|
        if HASHTAGS_TO_WATCH.map(&:upcase).include?(
            "##{(hashtag[:text]&.upcase)}"
          )
          includes_allowed_hashtags = true

          break
        end
      end

      includes_allowed_hashtags
    end

    def allowed_hashtag_count?(tweet)
      hashtags(tweet)&.count <= MAXIMUM_HASHTAG_COUNT
    end

    # Check if tweet is sensitive and has content that is not 
    # suitable for the bot to retweet
    def sensitive_tweet?(tweet)
      tweet.possibly_sensitive?
    end

    def should_re_tweet?(tweet)
      tweet?(tweet) && !retweet?(tweet) && 
      allowed_hashtag_count?(tweet) && 
      !sensitive_tweet?(tweet) && allowed_hashtags?(tweet)
    end

    def re_tweet(rest_client, stream_client)
      stream_client.filter(:track => HASHTAGS_TO_WATCH.join(',')) do |tweet|
        puts "\nCaught the tweet -> #{tweet.text}"

        if should_re_tweet?(tweet)
          rest_client.retweet tweet

          puts "[#{Time.now}] Retweeted successfully!\n"
        end
      end
    rescue StandardError => e
      puts "=========Error========\n#{e.message}"

      puts "[#{Time.now}] Waiting for 60 seconds ....\n"

      sleep 60
    end

    def twitter_api_config
      {
        consumer_key: ENV['CONSUMER_KEY'],
        consumer_secret: ENV['CONSUMER_SECRET'],
        access_token: ENV['ACCESS_TOKEN'],
        access_token_secret: ENV['ACCESS_TOKEN_SECRET']
      }
    end

    def configure_rest_client
      puts 'Configuring Rest Client'

      Twitter::REST::Client.new(config)
    end

    def configure_stream_client
      puts 'Configuring Stream Client'

      Twitter::Streaming::Client.new(config)
    end
  end
end

Twitter::ReTweetService.new.perform
