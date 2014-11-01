# Run this with the full set of options:
#   rails r script/translations/diff_generator.rb stable e883cb4056609f34c35aa26b097daa034d84ace4 -o ../translations/workcloud_translations_20140809.html
#
# Or run this with the interactive console:
#   rails r script/translations/diff_generator.rb
#
# Options:
# Specifying an output file
#   rails r script/translations/diff_generator.rb -o ../translations/workcloud_translations_20140809.html
# Specifying html output, but to screen only
#   rails r script/translations/diff_generator.rb -o
# Output as plain text to screen (e.g. if you want to check what the changes are before generating the file)
#   rails r script/translations/diff_generator.rb

require 'optparse'

class DiffParser
  def initialize(branch, start_sha)
    @branch = branch
    @start_sha = start_sha
  end

  def parse(options = {})
    @as_html = options[:html]

    @filecount = @new_filecount = @ja_count = 0
    @line_number = nil
    @view_path = @edit_path = ''
    @is_new = false

    @output_lines = diff_against_with_start_sha.split("\n").map do |line|
      next if line.match(/^index|^\-\-\- a|\-\-\- \/dev/)

      if line.match(/^diff \-\-/)
        # start of a new file diff
        @is_new = false
        next
      elsif line.match(/^new file/)
        # indicator this is a new file
        @is_new = true
        @new_filecount += 1
        next
      elsif match = line.match(/^(\+\+\+ b)(.+?)$/)
        line = filepath_line(line, match)
      elsif line.match(/^@@/)
        line = diff_block_start_line(line)
      elsif ignorable_text?(line)
        next
      else
        # should be all translations
        line = translation_line(line)
      end

      line
    end.flatten.compact

    add_summary

    return self
  end

  def output
    title = "Translations for #{Time.now.strftime('%Y-%m-%d %H:%M')}"

    if @as_html == :html
      # html output to console
      html_output(title).each do |line|
        puts line
      end
    elsif @as_html.is_a?(String)
      # html output to file
      File.open(@as_html, 'w'){ |f| f.write(html_output(title).join("\n")) }
    else
      puts "#{title}\n"
      puts "Branch: #{@branch}"
      puts "Old_point: #{@start_sha}"
      puts "New_point: #{`git rev-parse HEAD`.chomp}"
      puts @output_lines
    end
  end

  private

  def ignorable_text?(line)
    line.gsub(/(^\+|\-)/, '').strip.match(/^<.+>$/)
  end

  def html_output(title)
    html_lines = [html_header]

    title_lines = [
      "<h3>#{title}</h3>",
      "<p>Branch: #{@branch}</p>",
      "<p>Old_point: #{@start_sha}</p>",
      "<p>New_point: #{`git rev-parse HEAD`.chomp}</p>",
      '',
      'Click on any of the green translations to go directly to the edit page.',
    ]
    html_lines += title_lines

    html_lines += @output_lines.map do |line|
      klass = 'translation' if line.match(/<code/)
      %Q(<p class="#{klass}">#{line}</p>)
    end

    html_lines << html_footer
  end

  def diff_against_with_start_sha
    # only getting files that are in the subdir of /config/locales; this will ignore the en.yml/ja.yml output files
    command = %Q(git diff --unified=0  #{@start_sha}..#{@branch} -- `ls -d config/locales/*/`)
    diff = `#{command}`
  end

  def translation_line(line)
    code_class = translation_class(line)
    count_ja_translations(line)

    line = link_to_edit_path(line) if @as_html
    increment_line_number

    if @as_html
      # wrap html version in monospace tag
      line = %Q(<code class="#{code_class}">#{line}</code>)
    else
      line
    end
  end

  def increment_line_number
    @line_number += 1 if @line_number
  end

  def link_to_edit_path(line)
    if @line_number && line.match(/\+ /)
      # only increment line number if it's an added line,
      # otherwise '- ' deleted lines will also incorrectly be counted
      # line = "##{@line_number}: #{line}"
      line_path = "\n#{@edit_path}#L#{@line_number}"
      line = filepath(line_path, @line_number, line)
    else
      line
    end
  end

  # count the number of translations (+added only, so don't double-count changes)
  def count_ja_translations(line)
    if line.match(/^\+\s+ja:/)
      @ja_count += 1
    end
  end

  def translation_class(line)
    if line.match(/^\+ /)
      'add'
    elsif line.match(/^\- /)
      'delete'
    end
  end

  def filepath_line(line, match)
    @filecount += 1
    filename = match[2]
    @view_path = "https://github.com/workcloud/workcloud/blob/#{@branch}#{filename}"
    @edit_path = "https://github.com/workcloud/workcloud/edit/#{@branch}#{filename}"
    line = [
            line_separator(:top),
            "#{@is_new ? 'NEW' : 'CHANGED'}: #{filename}",
            "#{filepath(@view_path)}",
            line_separator(:bottom),
           ]
  end

  def diff_block_start_line(line)
    match = line.match(/^(.+?\+)(\d+)(.+?)/)
    if match
      @line_number = match[2].to_i
      line_path = "\n#{@view_path}#L#{@line_number}"
      line = filepath(line_path, nil, line_path, 'diff_block')
    end
  end

  def add_summary
    summary = "Summary: #{@new_filecount} new files, #{@filecount} changed files, #{@ja_count} translations added or changed."
    @output_lines.unshift "#{summary}"
    @output_lines.unshift ''
    @output_lines.push ''
    @output_lines.push "#{summary}"
  end

  def filepath(path, line_number = nil, line = nil, klass = nil)
    if @as_html
      klass ||= line_number ? 'edit_path' : ''
      if line
        caption = line
      else
        caption = line_number.nil? ? 'View file' : "Edit line ##{line_number}"
      end
      %Q(<a href="#{path.strip}" class="#{klass}" target="_blank">#{caption}</a>)
    else
      path
    end
  end

  def line_separator(position)
    if @as_html
      %Q(<hr class="#{position}"/>)
    else
      '========================================================'
    end
  end

  def html_header
    <<-HTML
<html>
<head>
  <style>
    body {
      font-family: Tahoma;
      font-size: 16px;
      line-height: 16px;
      padding: 10px 10px;
    }
    .wrapper {
      width: 800px;
      margin: 0 auto;
    }
    p {
      margin: 5px 0;
    }
    p.translation {
      margin: 0;
    }
    a {
      text-decoration: none;
    }
    a:hover {
      /*text-decoration: underline;*/
      background-color: #E8FFEA;
    }
    a.diff_block {
      display: block;;
      margin: 12px 0;
    }
    a.edit_path {
      display: block;
      /*padding: 3px 0;*/
    }
    code {
      font-family: Lucida Console;
      font-size: 14px;
      line-height: 20px;
      margin: 0;
      white-space: pre-wrap;
    }
    code.add {
      color: green;
    }
    code.add a{
      color: green;
    }
    code.delete {
      color: red;
    }
    code.delete a {
      color: red;
    }
    hr.top{
      margin-top: 20px;
    }
    hr.bottom{
      margin-bottom: 20px;
    }
  </style>
</head>
<body>
<div class="wrapper">
    HTML
  end

  def html_footer
    '</div></body><html>'
  end

end

options = {:html => false}
OptionParser.new do |opts|
  opts.on("-o", "--output [PATH]" , "Use HTML output, with optional output filepath") do |path|
    options[:html] = path.nil? ? :html : path
  end
end.parse!(ARGV)

if ARGV.size == 2
  branch, start_sha = ARGV
else
  print "Enter branch: "
  branch = $stdin.gets.chomp
  if branch.strip == ''
    exit
  end

  print "Enter starting SHA: "
  start_sha = $stdin.gets.chomp
  if start_sha.strip == ''
    exit
  end
end


DiffParser.new(branch, start_sha).parse(options).output
