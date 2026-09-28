/**
 * @description Builds an HttpRequest from a Web_Service_Setting__mdt record. Path__c placeholders are URL-encoded:
 *              {apiKey} comes from the record, the rest from the caller. An unresolved placeholder throws.
 * @author Apfeswaho Tshivhase
 * @date 2026-09-22
 */
public with sharing class WebServiceSettings {
  public static final String ERROR_SETTING_NOT_FOUND = 'Web service setting "{0}" is not configured (Setup > Custom Metadata Types > Web Service Setting).';
  public static final String ERROR_MISSING_API_KEY = 'Web service setting "{0}" uses {1} in its path but has no API Key.';
  public static final String ERROR_UNRESOLVED_PLACEHOLDER = 'Web service setting "{0}" has an unresolved placeholder {1} in its path.';
  public static final String API_KEY_PLACEHOLDER = 'apiKey';

  private static final Pattern PLACEHOLDER = Pattern.compile(
    '\\{([A-Za-z0-9_]+)\\}'
  );
  private static final String DEFAULT_HTTP_METHOD = 'GET';
  private static final Integer DEFAULT_TIMEOUT_MS = 30000;

  // Custom metadata can't be inserted in tests, so tests register records here.
  @TestVisible
  private static Map<String, Web_Service_Setting__mdt> settingOverrides = new Map<String, Web_Service_Setting__mdt>();

  public class SettingException extends Exception {
  }

  public static Web_Service_Setting__mdt getSetting(String developerName) {
    Web_Service_Setting__mdt setting = settingOverrides.containsKey(
        developerName
      )
      ? settingOverrides.get(developerName)
      : Web_Service_Setting__mdt.getInstance(developerName);
    if (setting == null) {
      throw new SettingException(
        String.format(
          ERROR_SETTING_NOT_FOUND,
          new List<String>{ developerName }
        )
      );
    }
    return setting;
  }

  /**
   * @param pathValues Path__c placeholder values, keyed by placeholder name
   */
  public static HttpRequest buildRequest(
    String developerName,
    Map<String, String> pathValues
  ) {
    Web_Service_Setting__mdt setting = getSetting(developerName);
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      'callout:' +
        setting.Named_Credential__c +
        mergePath(developerName, setting, pathValues)
    );
    request.setMethod(
      String.isBlank(setting.Http_Method__c)
        ? DEFAULT_HTTP_METHOD
        : setting.Http_Method__c
    );
    request.setTimeout(
      setting.Timeout_Ms__c == null
        ? DEFAULT_TIMEOUT_MS
        : setting.Timeout_Ms__c.intValue()
    );
    return request;
  }

  @TestVisible
  private static String mergePath(
    String developerName,
    Web_Service_Setting__mdt setting,
    Map<String, String> pathValues
  ) {
    String path = setting.Path__c == null ? '' : setting.Path__c;
    Map<String, String> values = pathValues == null
      ? new Map<String, String>()
      : new Map<String, String>(pathValues);
    if (path.contains('{' + API_KEY_PLACEHOLDER + '}')) {
      if (String.isBlank(setting.Api_Key__c)) {
        throw new SettingException(
          String.format(
            ERROR_MISSING_API_KEY,
            new List<String>{ developerName, '{' + API_KEY_PLACEHOLDER + '}' }
          )
        );
      }
      values.put(API_KEY_PLACEHOLDER, setting.Api_Key__c);
    }

    Matcher placeholders = PLACEHOLDER.matcher(path);
    String merged = path;
    while (placeholders.find()) {
      String name = placeholders.group(1);
      if (values.get(name) == null) {
        throw new SettingException(
          String.format(
            ERROR_UNRESOLVED_PLACEHOLDER,
            new List<String>{ developerName, '{' + name + '}' }
          )
        );
      }
      merged = merged.replace(
        '{' + name + '}',
        EncodingUtil.urlEncode(values.get(name), 'UTF-8')
      );
    }
    return merged;
  }
}
