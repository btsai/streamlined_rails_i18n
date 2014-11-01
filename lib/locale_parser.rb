# -*- coding: utf-8 -*-
# Run this manually with this from project root:
#   ruby lib/locale_parser.rb [optional regex string]
#   where regex string is like '.*?target'
# Or if this is included in application.rb restarting the rails server, or running a test will run this also automatically.

require 'yaml'
class LocaleParser

  def run(target_path = nil)
    time = Time.now
    if defined?(Rails) && (Rails.env.development? || Rails.env.test?)
      print "=> Parsing localization files. "
    else
      puts "> Parsing localization files..."
    end

    # holder for the output hash to yaml
    output = supported_languages.inject({}){ |hash, lang| hash[lang] = {}; hash }

    Dir.glob('config/locales/**/*') do |folder|
      next unless File.directory?(folder)

      # find all yml files that are NOT en.yml, ja.yml etc; we need to ignore those,
      # as they are either default files or our own generated files.
      files = Dir.glob(File.join(folder, '*.yml'))
      files.delete_if{ |f| f.match(/\/d(en|ja|zh)\.yml/) }
      next if files.empty?

      files.each do |path|
        # if a target path has been passed in, only process that one
        next if target_path && !path.match(Regexp.new(target_path))

        begin
          full_dictionary = YAML.load(File.read(path))
        rescue Psych::SyntaxError => err
          show_yaml_error(err, path)
        end

        next unless full_dictionary && full_dictionary.is_a?(Hash)

        # provide some debugging output if running the script directly
        puts "- #{path.gsub('config/locales/', '')} " unless defined?(Rails)

        if supported_languages.include?(full_dictionary.keys.first)
          # if there are default dictionaries, they are already on a language node so go one level down.
          lang, dictionary_node = full_dictionary.keys.first, full_dictionary.values.first
          map_single_language_strings(dictionary_node, output[lang])
        else
          # if this is a multi-lingual file, need to parse accordingly
          supported_languages.each do |lang|
            # iterate over all keys to map the right language
            map_multi_lingual_strings(full_dictionary, output[lang], lang)
          end
        end
      end
    end

    dump_hash_to_files(output)
    elapsed_time = sprintf('%.3f', Time.now - time)
    if defined?(Rails)
      puts "Done in #{elapsed_time}s."
    else
      puts "\n> Done in #{elapsed_time}s."
    end
  end

  private

  def show_yaml_error(err, path)
    print_red do
      message = "\n> ERROR: YAML error trying to parse locale file"
      match = err.message.match(/at line (\d+)/)
      message << " on line #{match[1]}" if match
      puts "#{message} located at:"
      puts "  #{path}\n\n"
    end
    puts "> Actual error message was:"
    print_red do
      puts err.message + "\n\n"
    end
    puts "This line might require single or double quotes around the string."
    puts "All symbols like ':', '%', '{}' etc need to be in single or double quotes"
    puts "You can debug this quicker by running the parsing script directly:\n$> ruby lib/locale_parser.rb"
    puts "\n\n"
    exit
  end

  def map_single_language_strings(dictionary_node, output_node)
    dictionary_node.each do |key, object_at_node|
      if object_at_node.is_a?(Hash)
        output_node[key] ||= {}
        map_single_language_strings(object_at_node, output_node)
      else
        output_node[key] ||= {}
        output_node[key] = object_at_node
      end
    end
  end

  # recursive function to chase down all nested hashes and find the right language string to map
  def map_multi_lingual_strings(dictionary_node, output_node, lang)
    dictionary_node.each do |key, object_at_node|
      # ignore any nodes that are the terminal translation, e.g. {:en => 'Name'}
      return unless object_at_node.is_a?(Hash)

      # object_at_node might be another nested hash
      if object_at_node.has_key?(lang)
        # an example of this condition is:
        #   {name => {:en => 'Name', :ja => 'JA name', :hint => {:en => '', :ja => ''}}}
        #     will have object_at_node of {:en => 'Name', :ja => 'JA name', :hint => {:en => '', :ja => ''}}

        # if there is a lang code node, then map that value to the output node
        output_node[key] = object_at_node[lang]

      else
        # an example of this condition is:
        #   {:activerecord => {:attributes => {}}}
        #     will have object_at_node {:attributes => {}}
        output_node[key] ||= {}
        map_multi_lingual_strings(object_at_node, output_node[key], lang)

      end
    end
  end

  def dump_hash_to_files(output)
    supported_languages.each do |lang|
      # generate yaml with top node set to the language node
      yaml_hash = {lang => output[lang]}
      yaml = hash_to_clean_yaml(yaml_hash)

      # output the file
      filepath = File.join('config/locales', "#{lang}.yml")
      File.open(filepath, 'w'){ |f| f.write(yaml) }
    end
  end

  def hash_to_clean_yaml(hash)
    # note that in ruby 1.9 keys are in the order they are inserted
    yaml = hash.to_yaml(:line_width => -1) # don't want line wrapping
    # remove the first line '---' which isn't needed
    yaml.split("\n")[1..-1].join("\n") + "\n"
  end

  def supported_languages
    # %w(en ja zh-CN zh-TW)
    %w(en ja)
  end

  def print_red
    add_print_code("\e[1;31m")
    yield
  ensure
    add_print_code("\e[0m")
  end

  def add_print_code(string = '')
    $stdout.print(string)
  end

end

if __FILE__ == $0
  # loads all files if no ARGV, or else the first arg matches the path
  LocaleParser.new.run(ARGV[0])
end
