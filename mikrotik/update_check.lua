# Checks for RouterOS updates on the configured channel and sends a Telegram
# notification if a newer version is available. Does NOT install automatically.

:local DeviceName [/system identity get name];

/system package update check-for-updates once;
:delay 10s;

:local installed [/system package update get installed-version];
:local latest    [/system package update get latest-version];
:local status    [/system package update get status];

:if ([:len $latest] = 0) do={
    :log warning "update_check: latest-version unavailable (offline?)";
    :return "";
}

:if ($installed != $latest) do={
    :local MessageText ("\F0\9F\9A\80 <b>" . $DeviceName . ":</b> RouterOS update available.%0A" . \
                        "<b>Installed:</b> <code>" . $installed . "</code>%0A" . \
                        "<b>Latest:</b> <code>" . $latest . "</code>%0A" . \
                        "<b>Status:</b> <code>" . $status . "</code>");
    :log info ("update_check: $installed -> $latest");
    :do {
        :local Send [:parse [/system script get tg_send source]];
        $Send MessageText=$MessageText;
    } on-error={};
} else={
    :log info ("update_check: already on latest ($installed)");
}
