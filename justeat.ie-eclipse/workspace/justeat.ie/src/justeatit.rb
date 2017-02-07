require 'rubygems'
require 'mongo'
require 'nokogiri'
require 'json'
require 'hpricot'
require 'open-uri'
require 'mechanize'
require 'logger'
require 'i18n'
require 'set'

include Mongo

puts "-------------- Connecting to mongo db -----------------------"

class String
  def string_between_markers marker1, marker2
    self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
  end
end


class CrawlJustEatIe

	  

  @agent
  @avoid
  @visits
  @stores
  
  def initialize(visitcol,storescol)
    @visits = visitcol                
    @stores = storescol
    Mechanize::Util::CODE_DIC[:SJIS] = "ISO-8859-1"
      @agent = Mechanize.new { |a| a.log = Logger.new("mech.log") }
      @agent.user_agent_alias = "Mac Safari"
  end
                             
                 
  def filter_accent(s)
    return I18n.transliterate(s)
  end
  
  
   def get_addr_data(addr_string)
     addr = {}
     filtered_string = filter_accent(addr_string)
     puts "The address is: " + filtered_string
     url = ("http://maps.google.com/maps/api/geocode/json?address=" + filtered_string + "&sensor=false")
     uri = (URI.parse (URI.encode(url.strip)))
     
     @res = JSON.parse(Net::HTTP.get_response(uri).body.to_s)

     if (addr_string.size > 6)
       count = 0 
       while ((@res.to_s.include? "ZERO_RESULTS") or (@res.to_s.include? "OVER")) and (count <= 10) do
         puts "get addr try again\n"
         sleep(2)
	 @res = JSON.parse(Net::HTTP.get_response(uri).body.to_s)
	 count = count + 1
       end
       if (count > 10)
         return nil
       end
       #puts @res.to_s
       lat = @res["results"][0]["geometry"]["location"]["lat"].to_s
       lng = @res["results"][0]["geometry"]["location"]["lng"].to_s
       puts "LAT: " + lat
       puts "LNG: " + lng
       addr[:address] = @res["results"][0]["formatted_address"].to_s
       addr[:lat] = @res["results"][0]["geometry"]["location"]["lat"].to_s
       addr[:lng] = @res["results"][0]["geometry"]["location"]["lng"].to_s
       addr
      end
    end


                             
     def getDataFrom(myurl,page)
       
       myaddrstr = page.parser.xpath("//*[@id='lblRestAddress']/text()").to_s
       zip = page.parser.xpath("//*[@id='lblRestZip']/text()").to_s
       myaddr = get_addr_data(myaddrstr + "," + zip + ",Ireland")
       if myaddr.nil?
         myaddr[:address] = "No address"
         myaddr[:lat] = "0.000000"
         myaddr[:lng] = "0.000000"
       end
       menu = page.parser.xpath("//*[contains(@class,\"H2MC\") or contains(@class,\"prdDe\") or contains(@class,\"prdAc\") or contains(@class,\"prdPr\")]")



       categories = []       
       prods = []
       prod = {}
       cate_str = ""
       options = []
       current_option = {}
       
       menu.each { |m|
                   newprod = false
                   currentHtmlPortion = m.to_html.to_s
                   #puts "========================================================================================="
                   #puts currentHtmlPortion
                   #puts "========================================================================================="

                   if (currentHtmlPortion.include? "H2MC")   # this is a category
                     if (prods.size > 0)
                       categories << ({ :category => cate_str , :products => prods })
                       prods = []
                     end
                     cate_str = m.inner_text.to_s.strip
                     puts "NEW CATEGORY -----> " + cate_str
                   else
                     if (currentHtmlPortion.include? "prdDe") #this is a product description
                       to_parse_description = Nokogiri::HTML.parse currentHtmlPortion
                       to_parse_name = to_parse_description
                       parsed_name = to_parse_name.xpath("//*/h6/text()").to_s.strip
                       parsed_description = to_parse_description.xpath("//*/div/text()").to_s.strip
                       prod[:name] = parsed_name
                       prod[:description] = parsed_description
                       puts "PRODUCT NAME -----> " + parsed_name + " PRODUCT DESCRIPTION -----> " + parsed_description
                    else
                       if (currentHtmlPortion.include? "prdAc") #this is a product option
                         if (!prod[:options])
                           prod[:options] = []
                         end                 
                         #if (options.size <= 0)
                         #  options = []
                         #end
                         parsed_options = Nokogiri::HTML.parse currentHtmlPortion
                         opt = parsed_options.xpath("//*/span/text()").to_s
                         if !opt.eql? ""
                           current_option[:option] = opt
                         end
                       else
                         if (currentHtmlPortion.include? "prdPr")  #this is an option  price
                           current_option[:price] = m.inner_text.to_s.strip
                           puts "FOUND OPTION ----> " + current_option[:option] + " FOUND PRICE -----> " + current_option[:price]
                           if (prod[:options].size==0)
                             prod[:price] = current_option[:price]
                           else
                             prod[:options] << (current_option).clone
                           end
                           current_option = {}
                         end
                       end
                     end 
                  end
                   

                  if (!prod[:name].nil? and !prod[:description].nil? and !prod[:options].nil? and newprod)
                    puts "Saving product => " + prod.to_s
                    prods << ({:product => prod.clone })
                    prod = {}  # new empty object
                  end
                   
       }

       puts "CATEGORIES ARE --------->" + categories
       
       
       clogosrc = page.parser.xpath("//*/div[starts-with(@class,\"imageContainer\")]/img/@src").to_s
       
       
       
       clogo = "http://www.just-eat.ie" + clogosrc
       cname = page.parser.xpath("//*/h1[@class=\"restInfoH1\"]/text()").to_s
       restaurant_category = page.parser.xpath("//*[@itemprop=\"servesCuisine\"]/text()").to_s
       download_img = `cd logos && mkdir #{cname.delete(" ").to_s } && cd #{cname.delete(" ").to_s} && wget #{clogo} && mv #{clogo.split('/').last} #{clogo.split('/').last + ".jpg"}`
       puts "Download logo " + clogo
       puts "Company logo: " + clogo
       
       delivery_data = page.parser.xpath("//*/div[@id=\"TermsCont\"]/table/tbody/tr/td/label/text()")
       
       marker1 = "?restid="
       marker2 = ");"

       storeid = page.parser.xpath("//*[@id=\"hplnkseeOpenHours\"]/@onclick").to_s.string_between_markers(marker1,marker2)


       contextpage = (@agent.get(myurl + "/pages/restopenhrours.aspx?restid=" + storeid))

       mon = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenMonday\"]/text()").to_s
       tue = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenTuesday\"]/text()").to_s
       wed = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenWednestay\"]/text()").to_s
       thu = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenThursday\"]/text()").to_s
       fri = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenFriday\"]/text()").to_s
       sat = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenSaturday\"]/text()").to_s
       sun = contextpage.parser.xpath("//*[@id=\"ctl00_ContentPlaceHolder1_lblOpenSunday\"]/text()").to_s


       
       minorder = delivery_data[0].to_s.slice!("Above")
       shippingcost = delivery_data[1].to_s
      

       store = {:store => { :info => {
                                      :storeid => '',
                                      :productname => '',
                                      :prodorstore => 'showstore',
                                      :sumallprods => '0',
                                      :companyid => '0',
                                      :companyname => cname.to_s,
                                      :companylogo => "logos/" + cname.delete(" ").to_s + "/" + clogo.split('/').last + ".jpg",
                                      :distance => '0',
                                      :shippingcost => shippingcost,
                                      :lat => myaddr[:lat].to_s,
                                      :lng => myaddr[:lng].to_s,
                                      :address => myaddr[:address].to_s,
                                      :usr_fb => "",
                                      :phone => ""
                           
                            }, :categories => categories,
                            :context => {
                                         :mon => (mon),
                                         :tue => (tue),
                                         :wed => (wed),
                                         :thu => (thu),
                                         :fri => (fri),
                                         :sat => (sat),
                                         :sun => (sun),
                                         :minorder => minorder
                                                            }
                          }
               }



       puts "JSON is: " + store.to_json
       return JSON.parse(store.to_json.encode("UTF-8"))
     
end

def filter_by_accent(s)
  return (I18n.transliterate(s).eql? s)
end

def visited?(link)
  return @visits.any?{|a| a[:link] == link}
end

def product?(page)

  return (page.uri.to_s.include? "/menu" )
  
end


def crawl(lin,level)
  begin
    if (!visited?(lin) and (level <= 10) and !(lin.include? "javascript") and !(lin.to_s.include? "https") and (lin.to_s.include? "http://www.just-eat.ie") and (lin.include? "http") and filter_by_accent(lin))
      puts "visiting link: " + lin.to_s
      page = @agent.get(lin)
      visited = { :link => lin.to_s } 
      @visits << visited
      if (self.product?(page))
        puts "Get data from store " + lin.to_s
	      @stores.insert(getDataFrom(lin,page))
        puts "Inserted to mongo"
      else
        page.links.each { |a|
          if (a.href.to_s.include?("www.just-eat.ie" ))
            crawl(a.href.to_s,(level+1))
          else
            if (!a.href.to_s.include? "http://")
              crawl("http://www.just-eat.ie" + a.href.to_s,(level+1))
            end
          end                
        }
      
      
      end
  
    end

  rescue Exception => e
    
      puts "Exception raised... continue on another link"
      puts e.message
  end
end


end                   
                             
                             
    @db = Connection.new('localhost').db('imhungry-1')
    @justeat = @db.collection('justeat.ie')
    @visits = []  #@justeat[:visits]
    @stores = @justeat[:stores]
    
    
    puts "Visit collection: " + @visits.to_s
    puts "Stores collection: "  + @stores.to_s
    

                                                
    @crawler = CrawlJustEatIe.new(@visits,@stores)
                                   
     
     
                                                
    @crawler.crawl("http://www.just-eat.ie/takeaways",0)
     
                             
