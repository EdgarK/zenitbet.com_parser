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
  %w(sport, home_team, away_team, date, time).each_with_index{|name, i| result << " #{name} => '#{args[i]}' " }
  puts result
  @count += 1
end




NAME_TRANSLATION = {'П1' => '1', 'Х' => 'X', 'П2' => '2', '1Х' => '1X', '12' => '12', 'Х2' => 'X2'}
SPORT_NAME_TRANSLATION = {'Футбол' => 'soccer', 'Хоккей' => 'hockey', 'Теннис' => 'tennis', 'Снукер' => 'snooker', 'Гандбол' => 'handball', 'Волейбол' => 'volleyball', 'Баскетбол' => 'basketball'}
#americanfootball


def fetch_html
  http = Net::HTTP.new('zenitbet.com', 80)
  cookies = "PHPSESSID=8s61dkn4c2d8rm48ccl064agb3; __utma=170375595.704838195.1354790217.1354790217.1354794732.2; __utmc=170375595; __utmz=170375595.1354790217.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none); WRUID=0; basket_style=0; __utmb=170375595.4.10.1354794732; _ym_visorc=b"
  request = Net::HTTP::Post.new "/line/loadline"
  request.set_form_data({'live' => 1})
  request.initialize_http_header({'Cookie' => cookies, 'charset' => "windows-1251"})

  Nokogiri::HTML(http.request(request).body.force_encoding("windows-1251").encode('utf-8'), nil, 'utf-8')
end

lines = {}
fetch_html.css("div.b-sport").each do |sport|
  name = sport.css("span.b-league-name-label")[0].text.split(". ")[1]
  lines[name] ||= []
  line = {}
  sport.children.each do |match|
    if match['class'] == 'b-league'
      labels = []
      match.css('table.t-league').children.each do |row|
        if row.name == 'thead'
          row.css('th').each do |column|
            labels << column.text
          end
        else
          line['periods'] ||= {}
          line['periods']['main_time'] ||= {}
          row.css('tr.o').css('td').each_with_index do |column, i|
            if ["Событие", "Дата"].include?(labels[i])
              line[labels[i]] = column.text.gsub(/(^  *)|(  *$)/, "") if !["", " ", "  "].include?(column.text) and i < labels.length
            else
              line['periods']['main_time'][labels[i]] = column.text.gsub(/(^  *)|(  *$)/, "") if !["", " ", "  "].include?(column.text) and i < labels.length
            end
          end
          ext_labels = Array(row.css('tr.t-league__ross').css('table > thead > tr > th')[1..-1]).map { |val| val.text }
          row.css('tr.t-league__ross').css('table > tbody > tr').each do |tr|
            time = tr.css('td > b').text
            line['periods'][time] ||= {}
            tr.css('td')[1..-1].each_with_index do |val, i|
              line['periods'][time][ext_labels[i]] = val.text.to_f unless ["", " ", "  "].include?(val.text)
            end
          end
          Array(row.css('tr.t-league__ross > td > div > div')).each do |bla|
            text = bla.text.gsub(bla.css('b')[0].text, "")
            line[bla.css('b')[0].text] = text unless ["", " ", "  "].include?(text)
          end
        end
      end
      line["home_team"], line["away_team"] = line["Событие"].split(" - ").map { |val| val.gsub(/(^ *)|( ?[0-9:*]+.*)|( *$)/, "") }
    else
      line['league'] = match.css('span.b-league-name-label').text.split(". ")[2..-1].join(". ")
    end

    lines[name] << line
  end
end





lines.each do |key, val|
  game = SPORT_NAME_TRANSLATION[key]
  if game
    val.each do |match|
      bookmaker_event = get_bookmaker_event(game, match["home_team"], match["away_team"], Time.now.to_s, match["Дата"])
      match['periods'].each do |name, period|
        if name == "main_time"
          per = "0"
        else
          per = name.gsub(/-.+/, "")
        end
        NAME_TRANSLATION.each do |k, v|
          create_or_update_bet(bookmaker_event, per, v, nil, period[k]) if period[k]
        end

        create_or_update_bet(bookmaker_event, per, "F1", period["Ф1"], period["Кф1"]) if period["Ф1"] && period["Кф1"]
        create_or_update_bet(bookmaker_event, per, "F2", period["Ф2"], period["Кф2"]) if period["Ф2"] && period["Кф2"]
        create_or_update_bet(bookmaker_event, per, "F1", period["Ф1"], period["К1"]) if period["Ф1"] && period["К1"]
        create_or_update_bet(bookmaker_event, per, "F2", period["Ф2"], period["К2"]) if period["Ф2"] && period["К2"]

        if period['Тот']
          create_or_update_bet(bookmaker_event, per, 'TO', period['Тот'], period['Бол'])
          create_or_update_bet(bookmaker_event, per, 'TU', period['Тот'], period['Мен'])
        end
      end
    end
  end
end
