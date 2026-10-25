{
    serviceRegistry."jellyfin".oidc = {
        redirectUris = nixos: ["${nixos.my.services.jellyfin.url}/sso/OID/redirect/authelia"];
        scopes = ["openid" "profile" "groups"];
        clientSettings = {
            public = false;
            require_pkce = true;
            pkce_challenge_method = "S256";
            access_token_signed_response_alg = "none";
            userinfo_signed_response_alg = "none";
            token_endpoint_auth_method = "client_secret_post";
        };
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.jellyfin.oidc;
            adminGroup = config.my.services.lldap.adminGroup;
            pluginConfigDir = "${config.services.jellyfin.dataDir}/plugins/configurations";
            jf = config.services.jellyfin;
        in {
            systemd.services.jellyfin-gen-sso-config = {
                description = "Write Jellyfin SSO-Auth plugin config and branding from derived OIDC secret";
                after = ["authelia-main-gen-oidc.service"];
                requires = ["authelia-main-gen-oidc.service"];
                before = ["jellyfin.service"];
                wantedBy = ["jellyfin.service"];
                serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = pkgs.writeShellScript "jellyfin-gen-sso-config" ''
                        set -euo pipefail
                        SECRET=$(cat ${config.sops.secrets."jellyfin/oidc_client_secret".path})
                        mkdir -p ${pluginConfigDir}
                        rm -f ${pluginConfigDir}/SSO-Auth.xml
                        cat > ${pluginConfigDir}/SSO-Auth.xml <<XMLEOF
                        <?xml version="1.0" encoding="utf-8"?>
                        <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                          <SamlConfigs />
                          <OidConfigs>
                            <item>
                              <key>
                                <string>authelia</string>
                              </key>
                              <value>
                                <PluginConfiguration>
                                  <OidEndpoint>${cfgOidc.issuerUrl}</OidEndpoint>
                                  <OidClientId>${cfgOidc.clientId}</OidClientId>
                                  <OidSecret>$SECRET</OidSecret>
                                  <Enabled>true</Enabled>
                                  <EnableAuthorization>true</EnableAuthorization>
                                  <EnableAllFolders>true</EnableAllFolders>
                                  <EnabledFolders />
                                  <AdminRoles>
                                    <string>${adminGroup}</string>
                                  </AdminRoles>
                                  <Roles>
                                    <string>family</string>
                                    <string>${adminGroup}</string>
                                  </Roles>
                                  <EnableFolderRoles>false</EnableFolderRoles>
                                  <EnableLiveTvRoles>false</EnableLiveTvRoles>
                                  <EnableLiveTv>false</EnableLiveTv>
                                  <EnableLiveTvManagement>false</EnableLiveTvManagement>
                                  <LiveTvRoles />
                                  <LiveTvManagementRoles />
                                  <FolderRoleMappings />
                                  <RoleClaim>groups</RoleClaim>
                                  <OidScopes>
                                    <string>groups</string>
                                  </OidScopes>
                                  <CanonicalLinks></CanonicalLinks>
                                  <DisableHttps>false</DisableHttps>
                                  <DoNotValidateEndpoints>false</DoNotValidateEndpoints>
                                  <DoNotValidateIssuerName>false</DoNotValidateIssuerName>
                                  <SchemeOverride>https</SchemeOverride>
                                  <!-- PAR always uses Basic auth, ignoring client_secret_post; Authelia doesn't require PAR. -->
                                  <DisablePushedAuthorization>true</DisablePushedAuthorization>
                                  <!-- @{claim} placeholder syntax is this plugin's own, not a standard template. -->
                                  <AvatarUrlFormat>@{picture}</AvatarUrlFormat>
                                </PluginConfiguration>
                              </value>
                            </item>
                          </OidConfigs>
                        </PluginConfiguration>
                        XMLEOF
                        chown ${jf.user}:${jf.group} ${pluginConfigDir}/SSO-Auth.xml
                        chmod 600 ${pluginConfigDir}/SSO-Auth.xml

                        # Official SSO login button (README); true auto-redirect needs unsupported script injection.
                        rm -f ${jf.configDir}/branding.xml
                        cat > ${jf.configDir}/branding.xml <<XMLEOF
                        <?xml version="1.0" encoding="utf-8"?>
                        <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                          <LoginDisclaimer>&lt;form action=&quot;${config.my.services.jellyfin.url}/sso/OID/start/authelia&quot;&gt;
                          &lt;button class=&quot;raised block emby-button button-submit&quot;&gt;
                            Sign in with SSO
                          &lt;/button&gt;
                        &lt;/form&gt;</LoginDisclaimer>
                          <CustomCss>a.raised.emby-button {
                          padding: 0.9em 1em;
                          color: inherit !important;
                        }

                        .disclaimerContainer {
                          display: block;
                        }</CustomCss>
                          <SplashscreenEnabled>false</SplashscreenEnabled>
                        </BrandingOptions>
                        XMLEOF
                        chown ${jf.user}:${jf.group} ${jf.configDir}/branding.xml
                        chmod 600 ${jf.configDir}/branding.xml
                    '';
                };
            };

            systemd.services.jellyfin = {
                bindsTo = ["jellyfin-gen-sso-config.service"];
                after = ["jellyfin-gen-sso-config.service"];
            };
        };
    };
}
