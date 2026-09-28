/**
 * @description Syncs a list of years from Calendarific, one per execute(). Used by the annual job and admin backfills.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-21
 */
public with sharing class HolidaySyncBatch implements Database.Batchable<Integer>, Database.AllowsCallouts {
  // One year per transaction: a callout can't follow DML, and a failed year can't sink the others.
  public static final Integer SCOPE_SIZE = 1;

  private final List<Integer> years;

  public HolidaySyncBatch(List<Integer> years) {
    this.years = years;
  }

  public static Id run(List<Integer> years) {
    return Database.executeBatch(new HolidaySyncBatch(years), SCOPE_SIZE);
  }

  public static Id runRange(Integer fromYear, Integer toYear) {
    List<Integer> years = new List<Integer>();
    for (Integer year = fromYear; year <= toYear; year++) {
      years.add(year);
    }
    return run(years);
  }

  public Iterable<Integer> start(Database.BatchableContext context) {
    return years;
  }

  public void execute(Database.BatchableContext context, List<Integer> scope) {
    for (Integer year : scope) {
      HolidaySyncService.syncYear(year);
    }
  }

  public void finish(Database.BatchableContext context) {
  }
}
