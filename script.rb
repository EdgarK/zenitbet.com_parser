#coding: utf-8
require "rubygems"
require 'net/http'
require 'nokogiri'


def create_or_update_bet(bookmaker_event, period, bet_variation, value, koef, direct_link = nil, commission = 0, is_lay = false, market = nil)
  puts "bookmaker_event => #{bookmaker_event}, period => #{period}, bet_variation => #{bet_variation}, value => #{value}, koef => #{koef}"
end

@count = 1

def get_bookmaker_event(*args)
  result = "#{ @count }."
  %w(sport, home_team, away_team, date, time).each_with_index { |name, i| result << " #{name} => '#{args[i]}' " }
  puts result
  @count += 1
end


class Translator
  NAME_TRANSLATION = {'П1' => 'ML1', 'Х' => 'X', 'П2' => '2', '1Х' => '1X', '12' => '12', 'Х2' => 'X2','Кф1' => 'F1', 'Кф2' => 'F2', 'К1' => 'F1', 'К2' => 'F2', 'Бол' => 'TO', 'Мен' => 'TU'}
  #SPORT_NAME_TRANSLATION = {'Футбол' => 'soccer', 'Хоккей' => 'hockey', 'Теннис' => 'tennis', 'Снукер' => 'snooker', 'Гандбол' => 'handball', 'Волейбол' => 'volleyball', 'Баскетбол' => 'basketball','Настольный теннис' => 'table_tennis'}
  DOUBLED_VALUES = {'Кф1' => 'Ф1', 'Кф2' => 'Ф2', 'К1' => 'Ф1', 'К2' => 'Ф2', 'Бол' => 'Тот', 'Мен' => 'Тот'}

  def initialize
    @sport = nil
  end


  def sport=(name=nil)
    @sport = name.gsub(/ /,'_')
    if name && !self.instance_variable_get("@#{@sport}")
      self.instance_variable_set("@#{@sport}", {})
    end

  end

  def sport_()
    @sport.gsub(/ /,'_')
  end

  def sport()
    @sport
  end

  def get_values(key, values)
    raise "No translation for #{key.inspect}" unless self.has?(key)
    translated = if val = self.instance_variable_get("@#{sport_}")[key]
            val
          else
            NAME_TRANSLATION[key]
          end

    [translated, values[DOUBLED_VALUES[key]], values[key]] if translated
  end

  def has?(key)
    (self.instance_variable_get("@#{sport_}").keys + NAME_TRANSLATION.keys + DOUBLED_VALUES.keys + DOUBLED_VALUES.values).include? key
  end

  def []=(key, val)
    self.instance_variable_get("@#{sport_}")[key] = val
  end
end

translation = Translator.new()
translation.sport = 'Футбол'
translation['П1'] = '1'




def fetch_html
  http = Net::HTTP.new('zenitbet.com', 80)
  request = (Net::HTTP::Get.new("/line/setdata?onlyview=1&all=1&game=&live=1&timeline=0&ross=1"))
  cookies = http.request(request).get_fields('set-cookie')
  cookies.map! { |c| c.split('; ')[0] }
  cookies = cookies.join('; ')
  request = Net::HTTP::Post.new "/line/loadline"
  request.set_form_data({'live' => 1})
  request.initialize_http_header({'Cookie' => cookies, 'charset' => "windows-1251"})

  Nokogiri::HTML(http.request(request).body.force_encoding("windows-1251").encode('utf-8'), nil, 'utf-8')
end


def get_labels(heads)
  labels = []
  heads.each { |head| labels << head.text.gsub(/(^  *)|(  *$)/, '') unless head.text == "" }
  labels
end

lines = {}
fetch_html.css('div.b-sport').each do |sport|
  name = sport.css('span.b-league-name-label')[0].text.split('. ')[1]
  lines[name] ||= []
  (sport.children.length / 2).times do |i|
    line = {}
    line['periods'] = {}
    line['periods']['main_line'] = {}
    line['additional_totals'] = {}
    line['league_name'] = sport.css('span.b-league-name-label')[i].text.split('. ')[2..-1].join('. ')
    league_body = sport.css('div.b-league')[i]
    matches = league_body.css('table.t-league')
    (matches.children.length / 2).times do |match_num|
      match_head = matches.css('thead')[match_num]
      labels = get_labels(match_head.css('th')[2..-1])
      match_body = league_body.css('table.t-league > tbody')[match_num]
      main_line = match_body.css('tr.o, tr.e')

      main_line.css('td')[2..-1].each_with_index { |column, index| line['periods']['main_line'][labels[index]] = column.text if !['', ' '].include?(column.text) && labels[index] }

      line['time'] = main_line.css('td')[0].text.gsub(/(^  *)|(  *$)/, "")
      line['event'] = main_line.css('td')[1].text
      line['home_team'], line['away_team'] = line['event'].split(" - ").map { |val| val.gsub(/(^ *)|( ?[0-9:*]+.*)|( *$)/, "") }

      additional_info = match_body.css('tr.t-league__ross > td > div')
      additional_lines = additional_info.css('table')
      additional_totals = additional_info.css('div')
      labels = get_labels(additional_lines.css('th'))
      additional_lines.css('tbody > tr').each do |row|
        line_name = row.css('td')[0].text.gsub(/[^0-9]+/, '')
        line['periods'][line_name] = {}
        row.css('td')[1..-1].each_with_index { |column, index| line['periods'][line_name][labels[index]] = column.text if !['', ' '].include?(column.text) }
      end
      additional_totals.each do |total|
        total_name = total.text.split(':')[0]
        total_value = Array(total.text.split(':')[1..-1]).join(':')
        line['additional_totals'][total_name] = total_value
      end
    end

    lines[name] << line.clone
  end
end


lines.each do |game, val|
  translation.sport = game
    val.each do |match|
      bookmaker_event = get_bookmaker_event(game, match['home_team'], match['away_team'], Time.now.to_s, match['time'])
      match['periods'].each do |name, period|
        if name == 'main_line'
          per = (%w(basketball tennis).include? game )? '-1' : '0'
        else
          per = name.gsub(/-.+/, '')
        end

        period.each do |k, v|
          if k && (values = translation.get_values(k, period))
            create_or_update_bet(bookmaker_event, per, *values)
          end

        end

      end
    end
end
