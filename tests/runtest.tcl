# use tcl::tm::path add /path/to/your/tm 
puts "[tcl::tm::path list]"

tcl::tm::path add [file dirname [file dirname [file normalize [info script]]]]

package require rltest

puts "Running tests: $argv"
puts [::rltest::runAllTests {*}$argv]
