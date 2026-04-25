# Creates a binary backup (.backup) and a config export (.rsc), then sends a
# Telegram notification with the resulting filename. Requires the `tg_send`
# script in /system script.

:local DeviceName [/system identity get name];
:local rawDate    [/system clock get date];
:local Time       [/system clock get time];
:local Ver        [/system package update get installed-version];

# Sanitize the date so the filename never contains '/' (would create subdirs
# under non-iso date-format settings such as mdy).
:local Date "";
:local n [:len $rawDate];
:for i from=0 to=($n - 1) do={
    :local ch [:pick $rawDate $i ($i + 1)];
    :if ($ch = "/") do={ :set ch "-"; }
    :set Date ($Date . $ch);
}

:local Filename "backup-$DeviceName-$Date-$Ver";

# Optional password for the binary backup. Leave empty to disable encryption.
:local BackupPassword "";

:do {
    :if ([:len $BackupPassword] > 0) do={
        /system backup save name=$Filename password=$BackupPassword;
    } else={
        /system backup save name=$Filename dont-encrypt=yes;
    }
    /export file=$Filename;
    :log info ("Backup created on $DeviceName: $Filename");
} on-error={
    :log error ("Backup FAILED on $DeviceName at $Date $Time");
    :do {
        :local ErrText "\E2\9D\8C <b>$DeviceName:</b> backup FAILED at <code>$Date $Time</code>.";
        :local Send [:parse [/system script get tg_send source]];
        $Send MessageText=$ErrText;
    } on-error={};
    :error "backup failed";
}

:local MessageText "\F0\9F\92\BE <b>$DeviceName:</b> backup created.%0A<b>File:</b> <code>$Filename</code>%0A<b>Version:</b> <code>$Ver</code>";
:do {
    :local Send [:parse [/system script get tg_send source]];
    $Send MessageText=$MessageText;
} on-error={
    :log warning "tg_send not available - skipping notification";
}
