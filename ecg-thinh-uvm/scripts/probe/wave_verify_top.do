onerror {resume}
run 200000
do "../scripts/gui/wave_tb_top_ecg_classifier.do"
puts "=== wave add count: [sizeof [info signals -level 0]]"
puts "WV_DONE"
quit -f
