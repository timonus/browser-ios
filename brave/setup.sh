#!/bin/bash

[[ -e setup.sh  ]] || { echo 'setup.sh must be run from brave directory'; exit 1; }

# Pro Tip for ad-hoc building: add your app id as an arg, like ./setup.sh org.foo.myapp

app_id=${1:-`whoami`.brave}
echo Using APPID of $app_id, you can customize using ./setup.sh org.foo.myapp

echo CUSTOM_BUNDLE_ID=$app_id > xcconfig/local-def.xcconfig
# Custom IDs get the BETA property set automatically
[[ $app_id != com.brave.ios.browser ]] && echo BETA=Beta >> xcconfig/local-def.xcconfig

sed -e "s/APPGROUP_PLACEHOLDER/group.$app_id/" Brave.entitlements.template > Brave.entitlements

# if a brave build, setup fabric and mixpanel
if [[ $app_id == com.brave.ios.browser* ]]; then
    if [ ! -f ~/.brave-fabric-keys ]; then
       echo "Missing ~/.brave-fabric-keys"
       exit 1
    fi
    if [ ! -f ~/.brave-mixpanel-key ]; then
       echo "Missing ~/.brave-mixpanel-key"
       exit 1
    fi
    dev_team_id="KL8N8XSYF4"
    sed -i '' -e "s/KEYCHAIN_PLACEHOLDER/$dev_team_id.$app_id/" Brave.entitlements
    echo "DEVELOPMENT_TEAM=$dev_team_id" >> xcconfig/local-def.xcconfig
    echo adding fabric
    echo "./Fabric.framework/run $(head -1 ~/.brave-fabric-keys) $(tail -1 ~/.brave-fabric-keys)" > build-system/.fabric-key-setup.sh
    sed -e s/FABRIC_KEY_REMOVED/$(head -1 ~/.brave-fabric-keys)/  BraveInfo.plist.template | sed -e s/MIXPANEL_TOKEN_REMOVED/$(head -1 ~/.brave-mixpanel-key)/ > BraveInfo.plist
else
    sed -i '' -e "s/KEYCHAIN_PLACEHOLDER/\$\(AppIdentifierPrefix\)$app_id/" Brave.entitlements
    >build-system/.fabric-key-setup.sh
    cat BraveInfo.plist.template > BraveInfo.plist
    echo "Please edit xcconfig/local-def.xcconfig to add your DEVELOPMENT_TEAM id (or else you will need to set this in Xcode)"
    echo "  It is found here: https://developer.apple.com/account/#/membership"
    echo "// DEVELOPMENT_TEAM=" >> xcconfig/local-def.xcconfig
fi

echo GENERATED_BUILD_ID=`date +"%y.%m.%d.%H"` >> xcconfig/build-id.xcconfig

npm update

node -e "require('./node_modules/ad-block/lib/regions.js').forEach((x) =>{ if (x.lang) {console.log(x.lang + ',' + x.uuid)} } )" > adblock-regions.txt

## setup sync
(cd ../Carthage/Checkouts/sync && brew install yarn; yarn install && yarn run build)

# setup niceware
(cd ../Carthage/Checkouts/niceware && brew install yarn; yarn install && yarn run build)

