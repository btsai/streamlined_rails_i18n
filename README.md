Streamlined Rails I18n
======================

A more efficient way of managing Rails I18n translations.

#### Overview

This uses the standard Rails I18n process to localize the UI.  

However, instead of creating and managing separate localization files, .e.g.  EN and JA files for English and Japanese, this allows you to combine all languages into one single file, and use a pre-parser (`LocaleParser`) to split them into their own language files.  

This merit of this is that it is much easier to see / add strings together in pairs in the same file, and prevents the litter of having multiple en.yml or ja.yml files sprinkled all throughout the different levels of the `config/locales' dir.  

If you have a project where you have bilingual translators (i.e. basically all multi-lingual projects), it becomes increasingly difficult if not impossible to efficiently manage the addition and deletion of new/old translations across multiple files. I started out with separate files, but after the 3rd file, I got tired of switching between files and eye-balling them, trying to make sure that they had the same nodes, etc.  

With this method, you get to see all of your translations together under one node, like this:  
```
timesheets:
  tabs:
    annual:
      en: Annual
      ja: 年次
    monthly:
      en: Monthly
      ja: 月次
    shifts:
      en: Shifts
      ja: シフト
  timesheet_management:
    en: Timesheet management
    ja: タイムシート管理

```

Isn't that easier to translate and also check if something is missing, versus toggling back and forth between two files like this (not all translators have vim set up with paired screens)?  
```
en:
  timesheets:
    tabs:
      annual: Annual
      monthly: Monthly
      shifts: Shifts
    timesheet_management: Timesheet management

```

```
ja:
  timesheets:
    tabs:
      annual: 年次
      monthly: 月次
      shifts: シフト
    timesheet_management: タイムシート管理

```


#### How the parser works:

The `LocaleParser` will look for all files in `config/locales` that do not match *en.yml or *ja.yml. This means that any existing files like en.yml and ja.yml will be ignored.  

It will then parse through all of the found files, and create a language file for each found language node, where all of the parent keys are mapped to that language key.  

The final output is one consolidated en.yml, ja.yml file each that contains all of the translations in the `config/locales` dir. These are the files that Rails uses.  


#### Generating localization files

##### File structure

This is just a recommended way of organizing your files. You can do whatever you want.  

1. Have one file per model, in the /models dir, following Rails convention.
2. Match one file per view folder in /views dir.
3. Rails infrastructure files are in /rails.
4. Other common view or model stuff put in /common/common.yml


##### File format (e.g. for views):

```
controller:
  view_name:
    string_name:
      en: English Translation
      ja: Japanese Translation
```
is split into en and ja yml files (en shown below, ja is the same):
```
en:
  controller:
    view_name:
      string_name: English Translation
```

##### Generation process:

* You can manually run the parser with:
```
ruby lib/strings_parser.rb [optional regex string]

  where regex string is like '.*?appr'
```


##### Alternative setup

I found manually running the script each time to be a bit tiring.

What I ended up doing was sticking this inside our Rails application.rb file, so it runs automatically whenever you start the Rails app. This way either restarting the server or running a test will generate the final files. When you're developing the UI, you need to restart the Rails server anyway to see the changes reflected, so yo might as well put it in there.  

Here's how you include it in application.rb:
```
#**************************************************************
# I18N - LOCALIZATION
#**************************************************************

# automatically parse our special combined language I18n files and output into individual language YAML dictionaries
LocaleParser.new.run if Rails.env.development? || Rails.env.test?

```

It doesn't add much time to the startup, particularly if you have an SSD drive. We have about 5,000 translations, each in EN and JA across 145 files, and it takes only ~0.6 sec to generate everything.


#### Other Tips

1. Shortcut method  

There is a Rails 'lazy' shorthand reference (t('.key_name'), note the prefix '.') when using translation strings in views etc in your code.  

*DON'T DO THIS*. You will forget you have these and as you extract partials or refactor your template code, this will bite you in the ass. I'm still suffering from this a year out. It's great in concept when you first start out, but it's a terrible thing to do. They should remove this from Rails.  

2. Additional tweaks  

You'll soon get very tired of typing these for model-based strings:  

```
activerecord.attributes.model_name.field_name
```
```
activerecord.errors.models.model_name.error_name
```

Add these three patches:  

Patch 1  
```
# put this somewhere like app/helpers or app/concerns
module I18nSupplementalHelper

  # utility method to get the translated field on an active record model
  def a(model_name, field_name, options = {})
    I18n.t(ar_key(model_name, field_name), options)
  end

  # utility method to get the translated error on an active record model
  def e(model_name, error_name, options = {})
    I18n.t(error_key(model_name, error_name), options)
  end

  def ar_key(model_name, field_name)
    "activerecord.attributes.#{model_name}.#{field_name}"
  end

  def error_key(model_name, error_name)
    "activerecord.errors.models.#{model_name}.#{error_name}"
  end

end
```

Patch 2  
```
# put this in vendor/patches/rails/i18n.rb
module I18n
  include I18nSupplementalHelper

  def english?
    I18n.locale.to_s == 'en'
  end

  def japanese?
    I18n.locale.to_s == 'ja'
  end

  module_function :a, :e, :ar_key, :error_key, :english?, :japanese?

end

```

Patch 3  
```
# put this in vendor/patches/rails/active_record/base.rb 
class ActiveRecord::Base

  # making the I18n.translate helper available in models
  # these should be in active record too!!!
  def self.t(translation, options = {})
    I18n.t(translation, options)
  end

  def t(translation, options = {})
    I18n.t(translation, options)
  end

  # utility methods to get the translated field name on an active record model
  include I18nSupplementalHelper
  extend I18nSupplementalHelper

end
```

Now, in your models, etc, you can shorten your access to model strings like this:

Before:
```
activerecord.attributes.model_name.field_name
```

```
activerecord.errors.models.model_name.error_name
```

After:
```
a(:model_name, :field_name)
or
a(:model_name, 'field_name.sub_node')
```

```
e(:model_name, :error_name)
or
e(:model_name, 'error_name.sub_node')
```

Isn't that easier? These should be default in Rails too.  


### Making Life Easy For Translators

Then there's the reality about a month into your project where not only are you generating new translation files, but you're going back and changing the base English strings as you change features etc.  

New files are easy - pass them over to your translator, get them translated, copy them to the config dir, run the parser (manually or automatically), commit. Easy-peasy.  

Now imagine you have a large change that affects 15 files with say 100 strings changed. Most likely your translator doesn't use git and definitely doesn't know how to do a git diff to try to find out what's been changed. Commenting on the changes doesn't work well either - you have to find the changes and then you have to remove all of your comments before committing. *More pain*.  

I've added a helpful little script that will generate an HTML file with the git diff, plus links to the files on github, AND as a special bonus if you allow your translators to touch your code (it works on our team), links to the exact line in the edit window on github.  

As a result of this tool:  

BEFORE  

1. Paste a git diff into an email to highlight changes for translators, together with attaching the 15 changed files.  
2. Have the translator futz around in each of the files, comparing against your email to find the changes.  
3. Email back the files.  
4. Copy and paste just the changed lines back into the original file - unless you're sure you haven't made any other changes to the file.  

NOW  

Run this:  
```
rails r script/translations/diff_generator.rb -o ../translations/20141102_stable.html
Enter branch: stable
Enter starting SHA: a94934b7618164a657bd66a21bfb7a5a64a48024
```
  
Get a file like this:  

<img src="http://cl.ly/image/2A3O1e213k1d/Image%202014-11-02%20at%206.48.25%20AM.png"/>

If your translator has edit rights, he/she can click on any of the changed / added lines and go immediately to the github edit window, edit the translation, and then save.  

You will need to pull whatever branch they worked on and run the parser manually and check in the en.yml etc files, but I'm sure you could even automate this process with some sort of github webhook.  


##### Usage tips

Use the starting SHA as the last commit that had translation changes. This will ensure that all of the changes that the translator made in the last batch are properly reflected in the HTML diff file.  


