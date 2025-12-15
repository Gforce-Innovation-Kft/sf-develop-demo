public with sharing class GitHubAppAuthService {
  private static final String GITHUB_API_URL = 'https://api.github.com';

  /**
   * Generate JWT token for GitHub App authentication
   */
  public static String generateJWT() {
    try {
      // Get settings from Custom Metadata
      GitHub_App_Settings__mdt settings = getSettings();
      String privateKeyBase64 = settings.Private_Key_Base64__c;
      String appId = settings.App_Id__c;

      System.debug('=== JWT Generation Debug ===');
      System.debug('App ID: ' + appId);
      System.debug('Private Key Length: ' + privateKeyBase64.length());

      // JWT Header
      Map<String, Object> header = new Map<String, Object>{
        'alg' => 'RS256',
        'typ' => 'JWT'
      };

      // JWT Payload
      Long issuedAt = DateTime.now().getTime() / 1000;
      Long expiresAt = issuedAt + 600; // 10 minutes (max allowed by GitHub)

      Map<String, Object> payload = new Map<String, Object>{
        'iat' => issuedAt,
        'exp' => expiresAt,
        'iss' => appId
      };

      // Create JWT (header.payload)
      String encodedHeader = base64UrlEncode(
        Blob.valueOf(JSON.serialize(header))
      );
      String encodedPayload = base64UrlEncode(
        Blob.valueOf(JSON.serialize(payload))
      );

      String unsignedToken = encodedHeader + '.' + encodedPayload;

      // Sign with RSA-SHA256
      Blob privateKeyBlob = EncodingUtil.base64Decode(privateKeyBase64);
      Blob signature = Crypto.sign(
        'RSA-SHA256',
        Blob.valueOf(unsignedToken),
        privateKeyBlob
      );
      String encodedSignature = base64UrlEncode(signature);

      String jwtToken = unsignedToken + '.' + encodedSignature;
      System.debug(
        'Generated JWT Token (first 50 chars): ' +
        jwtToken.substring(0, Math.min(50, jwtToken.length()))
      );

      return jwtToken;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to generate JWT: ' + e.getMessage()
      );
    }
  }

  /**
   * Get installation access token using JWT
   * These tokens expire after 1 hour and should be generated fresh for each request
   */
  public static String getInstallationToken() {
    try {
      String jwt = generateJWT();
      GitHub_App_Settings__mdt settings = getSettings();
      Integer installationId = Integer.valueOf(settings.Installation_Id__c);

      System.debug('=== Installation Token Request Debug ===');
      System.debug('Installation ID: ' + installationId);

      String endpoint =
        'callout:GitHub_API' +
        '/app/installations/' +
        installationId +
        '/access_tokens';

      System.debug('Endpoint: ' + endpoint);

      HttpRequest req = new HttpRequest();
      req.setEndpoint(endpoint);
      req.setMethod('POST');
      req.setHeader('Authorization', 'Bearer ' + jwt);
      req.setHeader('Accept', 'application/vnd.github+json');
      req.setHeader('X-GitHub-Api-Version', '2022-11-28');
      req.setTimeout(60000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      System.debug('Response Status: ' + res.getStatusCode());
      System.debug('Response Body: ' + res.getBody());

      if (res.getStatusCode() == 201) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        String token = (String) responseMap.get('token');
        System.debug('=== Installation Token Received ===');
        System.debug(
          'Token (first 20 chars): ' +
            token.substring(0, Math.min(20, token.length())) +
            '...'
        );
        System.debug('Token expires at: ' + responseMap.get('expires_at'));
        System.debug(
          'Token permissions: ' + JSON.serialize(responseMap.get('permissions'))
        );
        return token;
      } else {
        throw new AuraHandledException(
          'Failed to get installation token: ' +
            res.getStatusCode() +
            ' - ' +
            res.getBody()
        );
      }
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error getting installation token: ' + e.getMessage()
      );
    }
  }

  /**
   * Helper method to encode in Base64URL format (required for JWT)
   */
  private static String base64UrlEncode(Blob input) {
    String base64 = EncodingUtil.base64Encode(input);
    // Convert to Base64URL format
    return base64.replace('+', '-').replace('/', '_').replaceAll('=+$', '');
  }

  /**
   * Retrieve GitHub App settings from Custom Metadata
   */
  private static GitHub_App_Settings__mdt getSettings() {
    List<GitHub_App_Settings__mdt> settings = [
      SELECT
        App_Id__c,
        Installation_Id__c,
        Private_Key_Base64__c,
        Webhook_Secret__c
      FROM GitHub_App_Settings__mdt
      WHERE DeveloperName = 'salesforce_gforce_devhub'
      LIMIT 1
    ];

    if (settings.isEmpty()) {
      throw new AuraHandledException(
        'GitHub App Settings not found. Please configure Custom Metadata.'
      );
    }

    return settings[0];
  }
}
