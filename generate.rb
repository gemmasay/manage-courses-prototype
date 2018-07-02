#!/usr/bin/env ruby
# Grab courses-clean.json from search-and-compare-data repo
# Run './generate.rb'
require 'json'

file = File.read('courses-clean.json')
data = JSON.parse(file)
provider = 'Bath Spa University'
courses = data.select {|c| c['provider'] == provider }

prototype_data = {
  'multi-organisation': false,
  'training-provider-name': provider,
  'provider-code-name': courses.first['providerCodeName'],
  'provider-code': courses.first['providerCode'],
  'address-line-1': '123 Baker Street',
  'town': 'London',
  'postcode': 'SW1 1AA',
  'telephone': '0208 123 4567',
  'email': 'someemail@not-an-email.com',
  'website': 'http://www.a-provider-website.org.uk/',
}

# Map course data for the `imported from UCAS` view
prototype_data['ucasCourses'] = courses.map do |c|

  options = []
  qual = (c['qualifications'].include?('Postgraduate') || c['qualifications'].include?('Professional')) ? 'PGCE with QTS' : 'QTS'
  partTime = c['campuses'].map {|g| g['partTime'] }.uniq.reject {|r| r == "n/a"}.count > 0
  fullTime = c['campuses'].map {|g| g['fullTime'] }.uniq.reject {|r| r == "n/a"}.count > 0
  salaried = c['route'] == "School Direct training programme (salaried)" ? ' with salary' : ''

  if partTime
    options << "#{qual} part time#{salaried}"
  end

  if fullTime
    options << "#{qual} full time#{salaried}"
  end

  {
    regions: c['regions'].join(', '),
    accrediting: c['accrediting'] || provider,
    subjects: c['subjects'].map {|s| s.downcase.capitalize }.join(', '),
    ageRange: c['ageRange'].capitalize,
    name: c['name'],
    route: c['route'],
    qualifications: c['qualifications'].join(', '),
    providerCode: c['providerCode'],
    programmeCode: c['programmeCode'],
    schools: c['campuses'].map { |a| { name: a['name'], address: a['address'], code: a['code'] } },
    options: options
  }
end

prototype_data['ucasCourses'].sort_by! { |k| k[:name] }

# Find all schools across all courses and flatten into array of schools
prototype_data['schools'] = courses.map { |c| c['campuses'].map { |a| { name: a['name'], address: a['address'], code: a['code'] } } }.flatten.uniq
prototype_data['schools'].sort_by! { |k| k[:name] }

# Create a list of accreditors
prototype_data['accreditors'] = courses.uniq {|c| c['accrediting'] }.map  do |c|
  accrediting = c['accrediting']

  if accrediting.nil?
    accrediting = provider
  end

  {
    name: accrediting,
    slug: accrediting.downcase.gsub(/[^a-zA-Z0-9]/, '-'),
    subjects: []
  }
end

prototype_data['accreditors'].sort_by! { |k| k[:name] }

# Create a list of subjects
prototype_data['subjects'] = courses.uniq {|c| c['name'] }.map  do |c|
  {
    name: c['name'],
    slug: c['name'].downcase.gsub(' ', '-')
  }
end

prototype_data['subjects'].sort_by! { |k| k[:name] }

# Group courses by accrediting provider
courses_by_accrediting = {}
prototype_data['accreditors'].each { |c| courses_by_accrediting[c[:name]] = [] }
courses.each do |c|
  courses_by_accrediting[c['accrediting'] || provider] << c
end

# Group courses by subject
courses_by_subject = {}
prototype_data['subjects'].each { |c| courses_by_subject[c[:name]] = [] }
courses.each { |c| courses_by_subject[c['name']] << c }

courses_by_accreditor_and_subject = {}
prototype_data['accreditors'].each do |accrediting|
  courses_by_accreditor_and_subject[accrediting[:name]] = {}
  prototype_data['subjects'].each { |subject| courses_by_accreditor_and_subject[accrediting[:name]][subject[:name]] = [] }
end

courses.each do |course|
  courses_by_accreditor_and_subject[course['accrediting'] || provider][course['name']] << course

  subject = prototype_data['subjects'].find {|s| s[:name] == course['name']}
  prototype_data['accreditors'].find { |a| a[:name] == (course['accrediting'] || provider)}[:subjects] << subject
end

prototype_data['accreditors'].each {|a| a[:subjects].sort_by! { |k| k[:name] }.uniq! }

prototype_data['folded_courses'] = {}
prototype_data['options'] = []

# Fold courses
courses_by_accreditor_and_subject.each do |accrediting, courses_by_subject|
  prototype_data['folded_courses'][accrediting] = []

  courses_by_subject.to_a.each do |s|
    subject = s[0]
    subject_courses = s[1]
    options = []

    subject_courses.each do |sc|
      qual = sc['qualifications'].include?('Postgraduate') ? 'PGCE with QTS' : 'QTS'
      partTime = sc['campuses'].map {|g| g['partTime'] }.uniq.reject {|r| r == "n/a"}.count > 0
      fullTime = sc['campuses'].map {|g| g['fullTime'] }.uniq.reject {|r| r == "n/a"}.count > 0
      salaried = sc['route'] == "School Direct training programme (salaried)" ? ' with salary' : ''

      if partTime
        options << "#{qual} part time#{salaried}"
        prototype_data['options'] << "#{qual} part time#{salaried}"
      end

      if fullTime
        options << "#{qual} full time#{salaried}"
        prototype_data['options'] << "#{qual} full time#{salaried}"
      end
    end

    folded_course = {
     name: subject,
     courses: subject_courses.count,
     accrediting: subject_courses.map {|c| c['accrediting'] || provider }.uniq.sort,
     applicationsOpen: subject_courses.map {|c| c['campuses'].map {|g| g['applyFrom'] }}.flatten.uniq.reject {|r| r == "n/a"},
     schoolsWithVacancies: subject_courses.map {|c| c['campuses'].map {|g| g['name'] }}.flatten.uniq.sort,
     options: options.uniq.sort,
     flags: {
       partTime: subject_courses.map {|c| c['campuses'].map {|g| g['partTime'] }}.flatten.uniq.reject {|r| r == "n/a"}.count > 1,
       salary: subject_courses.map {|c| c['route'] }.flatten.uniq.include?("School Direct training programme (salaried)"),
       qualifications: subject_courses.map {|c| c['qualifications'] }.uniq.count > 1
     }
    }

    prototype_data['folded_courses'][accrediting] << folded_course if folded_course[:courses] > 0
  end
end

prototype_data['options'].uniq!

# Output to copy and paste into prototype
# puts "#{courses.count} courses folded into #{prototype_data['folded_courses'].count}"
File.open('lib/prototype_data.json', 'w') { |file| file.write(JSON.pretty_generate(prototype_data)) }
