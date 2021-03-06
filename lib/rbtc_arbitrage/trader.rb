module RbtcArbitrage
  class Trader
    attr_accessor :stamp, :mtgox, :paid, :received, :options, :percent, :amount_to_buy

    def initialize options={}
      @stamp   = {}
      @mtgox   = {}
      @options = options
      @options[:volume] ||= 0.01
      @options[:cutoff] ||= 2

      self
    end

    def trade
      fetch_prices
      log_info if options[:verbose]

      if options[:cutoff] > percent
        raise SecurityError, "Exiting because real profit (#{percent.round(2)}%) is less than cutoff (#{options[:cutoff].round(2)}%)"
      end

      execute_trade if options[:live]

      self
    end

    def execute_trade
      validate_env
      get_balance
      raise SecurityError, "--live flag is false. Not executing trade." unless options[:live]
      if options[:verbose]
        puts "Balances:"
        puts "stamp usd: $#{stamp[:usd].round(2)} btc: #{stamp[:usd].round(2)}"
        puts "mtgox usd: $#{mtgox[:usd].round(2)} btc: #{mtgox[:usd].round(2)}"
      end
      if stamp[:price] < mtgox[:price]
        if paid > stamp[:usd] || amount_to_buy > mtgox[:btc]
          raise SecurityError, "Not enough funds. Exiting."
        else
          puts "Trading live!" if options[:verbose]
          Bitstamp.orders.buy amount_to_buy, stamp[:price] + 0.001
          MtGox.sell! amount_to_buy, :market
          Bitstamp.transfer amount_to_buy, ENV['MTGOX_ADDRESS']
        end
      else
        if paid > mtgox[:usd] || amount_to_buy > stamp[:btc]
          raise SecurityError, "Not enough funds. Exiting."
        else
          puts "Trading live!" if options[:verbose]
          MtGox.buy! amount_to_buy, :market
          Bitstamp.orders.sell amount_to_buy, stamp[:price] - 0.001
          MtGox.withdraw amount_to_buy, ENV['BITSTAMP_ADDRESS']
        end
      end
    end

    def fetch_prices
      @amount_to_buy = options[:volume]
      stamp[:price] = Bitstamp.ticker.ask.to_f
      mtgox[:price] = MtGox.ticker.buy
      prices = [stamp[:price], mtgox[:price]]
      @paid = prices.min * 1.005 * amount_to_buy
      @received = prices.max * 0.994 * amount_to_buy
      @percent = ((received/paid - 1) * 100).round(2)
    end

    def log_info
      puts "Bitstamp: $#{stamp[:price].round(2)}"
      puts "MtGox: $#{mtgox[:price].round(2)}"
      lower_ex, higher_ex = stamp[:price] < mtgox[:price] ? %w{Bitstamp, MtGox} : %w{MtGox, Bitstamp}
      puts "buying #{amount_to_buy} btc from #{lower_ex} for $#{paid.round(2)}"
      puts "selling #{amount_to_buy} btc on #{higher_ex} for $#{received.round(2)}"
      puts "profit: $#{(received - paid).round(2)} (#{percent.round(2)}%)"
    end

    def validate_env
      ["KEY", "SECRET", "ADDRESS"].each do |suffix|
        ["MTGOX", "BITSTAMP"].each do |prefix|
          key = "#{prefix}_#{suffix}"
          if ENV[key].blank?
            raise ArgumentError, "Exiting because missing required ENV variable $#{key}."
          end
        end
      end

      MtGox.configure do |config|
        config.key = ENV["MTGOX_KEY"]
        config.secret = ENV["MTGOX_SECRET"]
      end

      Bitstamp.setup do |config|
        config.key = ENV["BITSTAMP_KEY"]
        config.secret = ENV["BITSTAMP_SECRET"]
      end
    end

    def get_balance
      balances = MtGox.balance
      @mtgox[:btc] = balances[0].amount.to_f
      @mtgox[:usd] = balances[1].amount.to_f
      balances = Bitstamp.balance if options[:live]
      @stamp[:usd] = balances["usd_available"].to_f
      @stamp[:btc] = balances["btc_available"].to_f
    end
  end
end