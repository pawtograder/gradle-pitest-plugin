# Releasing this plugin

This is the Pawtograder fork of [gradle-pitest-plugin](https://github.com/szpak/gradle-pitest-plugin). It is published
to Maven Central as:

    com.pawtograder.info.solidsoft.gradle.pitest:gradle-pitest-plugin

and it makes projects use the Pawtograder fork of PIT (`com.pawtograder.org.pitest:*`), *not* upstream PIT.

## What to bump

Everything version-related lives in `gradle.properties`:

| Property        | Meaning                                                                 |
|-----------------|-------------------------------------------------------------------------|
| `version`       | version of this plugin                                                   |
| `pitestVersion` | default PIT version the plugin puts on the classpath of client projects  |

`pitestVersion` is the single source of truth. At build time it is written into
`info/solidsoft/gradle/pitest/pitest-defaults.properties` inside the plugin jar and read back by
`PitestPlugin.DEFAULT_PITEST_VERSION`, so there is no second copy to keep in sync.

The PIT version must already be released to Maven Central under `com.pawtograder.org.pitest` (see the
[pitest fork](https://github.com/pawtograder/pitest)) before this plugin is released against it — otherwise every
client build breaks.

## Prerequisites (once)

* **JDK 11.** The build uses the Gradle 6.9.2 wrapper, which does not run on JDK 17+:

      export JAVA_HOME=$(/usr/libexec/java_home -v 11)

Both the Central Portal token and the signing key are already configured in `~/.gradle/gradle.properties`
(mode 600, outside this repo):

    mavenCentralUsername=<Central Portal user token name>
    mavenCentralPassword=<Central Portal user token password>
    signing.keyId=DFB8D3EB
    signing.password=<passphrase of the release key>
    signing.secretKeyRingFile=/Users/jon/.gnupg/secring.gpg

Releases are signed with **Jonathan Bell <jon@jonbell.net>, key `E876C482DFB8D3EB`** — the same key that signed
gradle-pitest-plugin 0.1.0 and the pitest fork 2.0.0, so consumers see a consistent signer.

`secring.gpg` is the legacy keyring format the Gradle signing plugin needs; regenerate it after a key change with:

    gpg --export-secret-keys E876C482DFB8D3EB > ~/.gnupg/secring.gpg && chmod 600 ~/.gnupg/secring.gpg

A new Central Portal token can be generated at <https://central.sonatype.com/account>. On CI, use environment
variables instead — `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD`, `SIGNING_KEY` (armored key),
`SIGNING_PASSWORD`. Never commit key material — `secring.gpg` and `*.gpg` are gitignored.

## Releasing

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 11)

# 1. bump 'version' (and 'pitestVersion' if needed) in gradle.properties, then:
./gradlew clean check

# 2. build the signed bundle and upload it to the Central Portal
./gradlew publishToCentral

# 3. review the deployment at https://central.sonatype.com/publishing/deployments and press "Publish"
#    (it is uploaded as USER_MANAGED, so nothing goes public until you do)

# 4. tag it
git tag -a release/$(grep '^version=' gradle.properties | cut -d= -f2) -m "Release ..."
git push --tags
```

The artifact usually shows up on <https://repo1.maven.org/maven2/com/pawtograder/info/solidsoft/gradle/pitest/gradle-pitest-plugin/>
within ~15 minutes of pressing Publish.

Releases on Maven Central are **permanent** — a version can never be replaced or deleted, only superseded. Check the
staged bundle (`build/staging-deploy`) if in doubt.

### Useful tasks

| Task                            | Does                                                                              |
|---------------------------------|-----------------------------------------------------------------------------------|
| `./gradlew publishToMavenLocal` | installs into `~/.m2` for trying the plugin out in a client project locally        |
| `./gradlew centralBundle`       | stages + signs into `build/staging-deploy` and zips `build/central-bundle-*.zip`   |
| `./gradlew publishToCentral`    | the above, then uploads (`gradle/upload-to-central.sh`)                            |

Set `PUBLISHING_TYPE=AUTOMATIC` to skip the manual "Publish" click in the Portal.

## Telling clients

Client projects pin the plugin in their `buildscript` block, so they have to bump it themselves:

```groovy
buildscript {
    repositories { mavenCentral() }
    dependencies {
        classpath 'com.pawtograder.info.solidsoft.gradle.pitest:gradle-pitest-plugin:1.0.0'
    }
}
apply plugin: 'com.pawtograder.info.solidsoft.pitest'
```

As of plugin 1.0.0 the default PIT version is a *release* (2.0.0), so clients no longer need the
`https://central.sonatype.com/repository/maven-snapshots/` repository in their `buildscript` and `repositories` blocks.

A client can override the PIT version without a new plugin release:

```groovy
pitest {
    pitestVersion = '2.0.1'
}
```
