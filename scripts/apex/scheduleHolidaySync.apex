// Register the annual holiday sync (02:00 on 1 January: current year + next year). Run once per org:
//   sf apex run -o <org> -f scripts/apex/scheduleHolidaySync.apex
Id cronId = HolidaySyncScheduler.scheduleAnnual();
System.debug('Scheduled ' + HolidaySyncScheduler.JOB_NAME + ' as ' + cronId);
