// ============================================================================
// VERIFY GITHUB APP PERMISSIONS
// ============================================================================
// Run this to check if your GitHub App has the correct permissions
// for repository_dispatch events
// ============================================================================

System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
System.debug('🔍 Checking GitHub App Permissions...');
System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

try {
    // Get installation token
    String token = GitHubAppAuthService.getInstallationToken();
    System.debug('✅ Token retrieved successfully');

    // Call GitHub API to get installation details
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:GitHub_API/installation/repositories');
    req.setMethod('GET');
    req.setHeader('Authorization', 'Bearer ' + token);
    req.setHeader('Accept', 'application/vnd.github+json');
    req.setHeader('X-GitHub-Api-Version', '2022-11-28');

    Http http = new Http();
    HttpResponse res = http.send(req);

    if (res.getStatusCode() == 200) {
        Map<String, Object> response = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());

        // Extract permissions
        if (response.containsKey('repositories')) {
            List<Object> repos = (List<Object>)response.get('repositories');
            if (repos.size() > 0) {
                Map<String, Object> repo = (Map<String, Object>)repos[0];
                Map<String, Object> permissions = (Map<String, Object>)repo.get('permissions');

                System.debug('');
                System.debug('📋 Current Permissions:');
                System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

                // Check each required permission
                String actionsPermission = (String)permissions.get('actions');
                String contentsPermission = (String)permissions.get('contents');
                String metadataPermission = (String)permissions.get('metadata');

                System.debug('Actions:  ' + actionsPermission +
                    (actionsPermission == 'write' ? ' ✅' : ' ❌ Need: write'));
                System.debug('Contents: ' + contentsPermission +
                    (contentsPermission == 'write' ? ' ✅' : ' ❌ Need: write'));
                System.debug('Metadata: ' + metadataPermission +
                    (metadataPermission == 'read' ? ' ✅' : ''));

                System.debug('');

                // Final verdict
                if (contentsPermission == 'write' && actionsPermission == 'write') {
                    System.debug('✅ ✅ ✅ ALL PERMISSIONS CORRECT! ✅ ✅ ✅');
                    System.debug('You can use repository_dispatch!');
                } else {
                    System.debug('❌ ❌ ❌ PERMISSIONS MISSING! ❌ ❌ ❌');
                    System.debug('');
                    if (contentsPermission != 'write') {
                        System.debug('⚠️  Need: Contents = "write"');
                        System.debug('📖 Fix: https://github.com/settings/apps → Your App → Repository permissions');
                        System.debug('    Change "Contents" from "read" to "Read and write"');
                    }
                    if (actionsPermission != 'write') {
                        System.debug('⚠️  Need: Actions = "write"');
                    }
                    System.debug('');
                    System.debug('📝 After updating, remember to:');
                    System.debug('   1. Save changes in GitHub App settings');
                    System.debug('   2. Accept new permissions in installation settings');
                }

                System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

            } else {
                System.debug('❌ No repositories found. Is the app installed?');
            }
        }

    } else {
        System.debug('❌ API call failed: ' + res.getStatusCode());
        System.debug('Response: ' + res.getBody());
    }

} catch (Exception e) {
    System.debug('❌ Error: ' + e.getMessage());
    System.debug('Stack trace: ' + e.getStackTraceString());
}

System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

