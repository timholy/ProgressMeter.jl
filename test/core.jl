# test durationstring output at borders
@test ProgressMeter.durationstring(0.9) == "0:00:00"
@test ProgressMeter.durationstring(1.0) == "0:00:01"
@test ProgressMeter.durationstring(59.9) == "0:00:59"
@test ProgressMeter.durationstring(60.0) == "0:01:00"
@test ProgressMeter.durationstring(60*60 - 0.1) == "0:59:59"
@test ProgressMeter.durationstring(60*60) == "1:00:00"
@test ProgressMeter.durationstring(60*60*24 - 0.1) == "23:59:59"
@test ProgressMeter.durationstring(60*60*24) == "1 days, 0:00:00"
@test ProgressMeter.durationstring(60*60*24*10 - 0.1) == "9 days, 23:59:59"
@test ProgressMeter.durationstring(60*60*24*10) == "10.00 days"

@test ProgressMeter.Progress(5, "Progress:", Int16(5)).offset == 5
@test ProgressMeter.ProgressThresh(0.2, "Progress:", Int16(5)).offset == 5
