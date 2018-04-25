MATVER="2.6.0.4"

osp_detect() {
  case $1 in
    *.conf) SPACES=$(sed -n "/^output_session_processing {/,/^}/ {/^ *music {/p}" $1 | sed -r "s/( *).*/\1/")
            EFFECTS=$(sed -n "/^output_session_processing {/,/^}/ {/^$SPACES\music {/,/^$SPACES}/p}" $1 | grep -E "^$SPACES +[A-Za-z]+" | sed -r "s/( *.*) .*/\1/g")
            for EFFECT in ${EFFECTS}; do
              SPACES=$(sed -n "/^effects {/,/^}/ {/^ *$EFFECT {/p}" $1 | sed -r "s/( *).*/\1/")
              [ "$EFFECT" != "atmos" ] && sed -i "/^effects {/,/^}/ {/^$SPACES$EFFECT {/,/^$SPACES}/ s/^/#/g}" $1
            done;;
     *.xml) EFFECTS=$(sed -n "/^ *<postprocess>$/,/^ *<\/postprocess>$/ {/^ *<stream type=\"music\">$/,/^ *<\/stream>$/ {/<stream type=\"music\">/d; /<\/stream>/d; s/<apply effect=\"//g; s/\"\/>//g; p}}" $1)
            for EFFECT in ${EFFECTS}; do
              [ "$EFFECT" != "atmos" ] && sed -ri "s/^( *)<apply effect=\"$EFFECT\"\/>/\1<\!--<apply effect=\"$EFFECT\"\/>-->/" $1
            done;;
  esac
}

keytest() {
  ui_print " - Vol Key Test -"
  ui_print "   Press Vol Up:"
  (/system/bin/getevent -lc 1 2>&1 | /system/bin/grep VOLUME | /system/bin/grep " DOWN" > $INSTALLER/events) || return 1
  return 0
}

chooseport() {
  #note from chainfire @xda-developers: getevent behaves weird when piped, and busybox grep likes that even less than toolbox/toybox grep
  while (true); do
    /system/bin/getevent -lc 1 2>&1 | /system/bin/grep VOLUME | /system/bin/grep " DOWN" > $INSTALLER/events
    if (`cat $INSTALLER/events 2>/dev/null | /system/bin/grep VOLUME >/dev/null`); then
      break
    fi
  done
  if (`cat $INSTALLER/events 2>/dev/null | /system/bin/grep VOLUMEUP >/dev/null`); then
    return 0
  else
    return 1
  fi
}

chooseportold() {
  # Calling it first time detects previous input. Calling it second time will do what we want
  $KEYCHECK
  $KEYCHECK
  SEL=$?
  if [ "$1" == "UP" ]; then
    UP=$SEL
  elif [ "$1" == "DOWN" ]; then
    DOWN=$SEL
  elif [ $SEL -eq $UP ]; then
    return 0
  elif [ $SEL -eq $DOWN ]; then
    return 1
  else
    ui_print "   Vol key not detected!"
    abort "   Use name change method in TWRP"
  fi
}

# Tell user aml is needed if applicable
if $MAGISK; then
  if $BOOTMODE; then LOC="/sbin/.core/img/*/system $MOUNTPATH/*/system"; else LOC="$MOUNTPATH/*/system"; fi
  FILES=$(find $LOC -type f -name "*audio_effects*.conf" -o -name "*audio_effects*.xml")
  if [ ! -z "$FILES" ] && [ ! "$(echo $FILES | grep '/aml/')" ]; then
    ui_print " "
    ui_print "   ! Conflicting audio mod found!"
    ui_print "   ! You will need to install !"
    ui_print "   ! Audio Modification Library !"
    sleep 3
  fi
fi

# GET OLD/NEW FROM ZIP NAME
case $(basename $ZIP) in
  *old*|*Old*|*OLD*) MID=false; NEW=false; MAT=false;;
  *mid*|*Mid*|*MID*) MID=true; NEW=false; MAT=false;;
  *new*|*New*|*NEW*) MID=false; NEW=true; MAT=false;;
  *omat*|*Omat*|*OMAT*) NMAT=false; MAT=true;;
  *ndrv*|*Ndrv*|*NDRV*) NMAT=true; NDRV=true; MAT=true;;
  *odrv*|*Odrv*|*ODRV*) NMAT=true; NDRV=false; MAT=true;;
esac

# Check API compatibility
NEWONLY=false; PATCH=true
if [ $API -le 15 ]; then
  DRV=ics_$ABI
else
  DRV=jb_$ABI
fi
if [ $API -le 10 ]; then
  ui_print " "
  ui_print "   Gingerbread rom detected!"
  ui_print "   Only v2.3.4.0 is compatible!"
  MID=false; NEW=false; MAT=false; PATCH=false
  # Detect driver compatibility
  ui_print " "
  ABIVER=$(echo $ABILONG | sed -r 's/.*-v([0-9]*).*/\1/')
  [ -z $ABIVER ] && ABIVER=0
  CPUFEAT=$(cat /proc/cpuinfo | grep 'Features')
  if [ $ABIVER -ge 7 ] || [ "$(echo $CPUFEAT | grep 'neon')" ]; then
    ui_print "   Neon Device detected!"
    DRV=arm
  elif [ "$ABI" == "x86" ]; then
    ui_print "   x86 Device detected!"
    DRV=x86
  elif [ "$(echo $CPUFEAT | grep 'vfp')" ]; then
    ui_print "   Non-neon VFP Device detected!"
    DRV=VFP
  else
    ui_print "   Non-Neon, Non-VFP Device detected!"
    DRV=NOVFP
  fi
elif [ $API -le 24 ]; then
  ui_print " "
  ui_print "   Only v2.5.0.5 and newer is compatible!"
  NEWONLY=true
  $NEW || [ -z $MID ] || { ui_print "   Incompatible zipname option detected!"; ui_print "   You will need to choose a compatible one!"; MAT=""; }
fi

# Keycheck binary by someone755 @Github, idea for code below by Zappo @xda-developers
KEYCHECK=$INSTALLER/common/keycheck
chmod 755 $KEYCHECK

ui_print " "
ui_print "   Removing remnants from past v4a installs..."
# Uninstall existing v4a installs
V4AAPPS=$(find /data/app -type d -name "*com.pittvandewitt.viperfx*" -o -name "*com.audlabs.viperfx*" -o -name "*com.vipercn.viper4android_v2*")
if [ "$V4AAPPS" ]; then
  if $BOOTMODE; then
    for APP in ${V4AAPPS}; do
      case $APP in
        *com.pittvandewitt.viperfx*) pm uninstall com.pittvandewitt.viperfx >/dev/null 2>&1;;
        *com.audlabs.viperfx*) pm uninstall com.audlabs.viperfx >/dev/null 2>&1;;
        *com.vipercn.viper4android*) pm uninstall com.vipercn.viper4android_v2 >/dev/null 2>&1;;
      esac
    done
  else
    for APP in ${V4AAPPS}; do
      rm -rf $APP
    done
  fi
fi
# Remove remnants of any old v4a installs
for REMNANT in $(find /data -name "*ViPER4AndroidFX*" -o -name "*com.pittvandewitt.viperfx*" -o -name "*com.audlabs.viperfx*" -o -name "*com.vipercn.viper4android_v2*"); do
  [ "$(echo $REMNANT | cut -d '/' -f-4)" == "/data/media/0" ] && continue
  if [ -d "$REMNANT" ]; then
    rm -rf $REMNANT
  else
    rm -f $REMNANT
  fi
done

case $ABILONG in
  arm64*) JNID=arm64; JNI=arm;;
  arm*) JNID=arm; JNI=arm;;
  x86_64*) JNID=x86_64; JNI=x86;;
  x86*) JNID=x86;  JNI=x86;;
  *64*) JNID=arm64; JNI=arm;;
  *) JNID=arm; JNI=arm;;
esac

ui_print " "
if [ -z $MAT ]; then
  if keytest; then
    FUNCTION=chooseport
  else
    FUNCTION=chooseportold
    ui_print "   ! Legacy device detected! Using old keycheck method"
    ui_print " "
    ui_print "- Vol Key Programming -"
    ui_print "   Press Vol Up Again:"
    $FUNCTION "UP"
    ui_print "   Press Vol Down"
    $FUNCTION "DOWN"
  fi
  ui_print " "
  ui_print " - Select Version -"
  ui_print "   Choose which V4A you want installed:"
  ui_print "   Vol+ = material, Vol- = original"
  if $FUNCTION; then
    MAT=true
    ui_print " "
    ui_print "   Choose which material V4A you want installed:"
    ui_print "   Vol+ = new ($MATVER), Vol- = old (2.5.0.5)"
    if $FUNCTION; then
      NMAT=true
    else
      NMAT=false
    fi
  else
    MAT=false
    if $NEWONLY; then
      NEW=true
    else
      ui_print " "
      ui_print "   Choose which original V4A you want installed:"
      ui_print "   Vol+ = new (2.5.0.5), Vol- = older"
      if $FUNCTION; then
        NEW=true
      else
        NEW=false
        ui_print " "
        ui_print "   Choose which older V4A you want installed:"
        ui_print "   2.3.4.0 V4A will install super quality driver"
        ui_print "   Vol+ = 2.4.0.1, Vol- = 2.3.4.0"
        if $FUNCTION; then
          MID=true
        else
          MID=false
        fi
      fi
    fi
  fi
else
  ui_print "   V4A version specified in zipname!"
fi

V4ALIB=libv4a_fx_ics.so
mkdir -p $INSTALLER/system/lib/soundfx $INSTALLER/system/etc/permissions $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI
if $MAT; then
  if $NMAT; then
    ui_print "   New material V4A will be installed"
    V4ALIB=libv4a_fx.so
    if [ -z $NDRV ]; then
      ui_print " "
      ui_print "   Choose which driver you want installed:"
      ui_print "   Vol+ = 2.5.0.4, Vol- = 2.3.4.0"
      if $FUNCTION; then
        NDRV=true
      else
        NDRV=false
      fi
    fi
    if $NDRV; then
      ui_print "   2.5.0.5 driver will be installed"
      cp -f $INSTALLER/custom/2.5/libv4a_fx_$DRV.so $INSTALLER/system/lib/soundfx/$V4ALIB
    else
      ui_print "   2.3.4.0 driver will be installed"
      cp -f $INSTALLER/custom/2.3/libv4a_fx_$DRV.so $INSTALLER/system/lib/soundfx/$V4ALIB
    fi
    rm -rf $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI
    JNI=$JNID
    mkdir -p $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI
    cp -f $INSTALLER/custom/mat/libV4AJniUtils_$JNI.so $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI/libV4AJniUtils.so
    cp -f $INSTALLER/custom/mat/ViPER4AndroidFX.apk $INSTALLER/system/app/ViPER4AndroidFX/ViPER4AndroidFX.apk
  else
    MATVER="2.5.0.5"
    ui_print "   Old material V4A will be installed"
    cp -f $INSTALLER/custom/2.5/libv4a_fx_$DRV.so $INSTALLER/system/lib/soundfx/$V4ALIB
    cp -f $INSTALLER/custom/2.5/libV4AJniUtils_$JNI.so $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI/libV4AJniUtils.so
    cp -f $INSTALLER/custom/mat/ViPER4AndroidFXOld.apk $INSTALLER/system/app/ViPER4AndroidFX/ViPER4AndroidFX.apk
  fi
  cp -f $INSTALLER/custom/mat/privapp-permissions-com.pittvandewitt.viperfx.xml $INSTALLER/system/etc/permissions/privapp-permissions-com.pittvandewitt.viperfx.xml
  sed -ri -e "s/version=(.*)/version=\1 ($MATVER)/" -e "s/name=(.*)/name=\1 Materialized/" $INSTALLER/module.prop
  sed -i "s/author=.*/author=ViPER520, ZhuHang, Team_Dewitt, Ahrion, Zackptg5/" $INSTALLER/module.prop
  $LATESTARTSERVICE && sed -i 's/<ACTIVITY>/com.pittvandewitt.viperfx/g' $INSTALLER/common/service.sh
elif $NEW; then
  ui_print "   V4A 2.5.0.5 will be installed"
  cp -f $INSTALLER/custom/2.5/libv4a_fx_$DRV.so $INSTALLER/system/lib/soundfx/$V4ALIB
  cp -f $INSTALLER/custom/2.5/privapp-permissions-com.audlabs.viperfx.xml $INSTALLER/system/etc/permissions/privapp-permissions-com.audlabs.viperfx.xml
  cp -f $INSTALLER/custom/2.5/libV4AJniUtils_$JNI.so $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI/libV4AJniUtils.so
  cp -f $INSTALLER/custom/2.5/ViPER4AndroidFX.apk $INSTALLER/system/app/ViPER4AndroidFX/ViPER4AndroidFX.apk
  sed -ri "s/version=(.*)/version=\1 (2.5.0.5)/" $INSTALLER/module.prop
  $LATESTARTSERVICE && sed -i 's/<ACTIVITY>/com.audlabs.viperfx/g' $INSTALLER/common/service.sh
elif $MID; then
  ui_print "   V4A 2.4.0.1 will be installed"
  cp -f $INSTALLER/custom/2.4/libv4a_fx_$DRV.so $INSTALLER/system/lib/soundfx/$V4ALIB
  cp -f $INSTALLER/custom/2.4/privapp-permissions-com.vipercn.viper4android_v2.xml $INSTALLER/system/etc/permissions/privapp-permissions-com.vipercn.viper4android_v2.xml
  cp -f $INSTALLER/custom/2.4/libV4AJniUtils_$JNI.so $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI/libV4AJniUtils.so
  cp -f $INSTALLER/custom/2.4/ViPER4AndroidFX.apk $INSTALLER/system/app/ViPER4AndroidFX/ViPER4AndroidFX.apk
  sed -ri "s/version=(.*)/version=\1 (2.4.0.1)/" $INSTALLER/module.prop
  $LATESTARTSERVICE && sed -i 's/<ACTIVITY>/com.vipercn.viper4android_v2/g' $INSTALLER/common/service.sh
  LIBPATCH="\/system"; LIBDIR=/system; DYNAMICOREO=false
else
  ui_print "   V4A 2.3.4.0 will be installed"
  cp -f $INSTALLER/custom/2.3/libv4a_fx_$DRV.so $INSTALLER/system/lib/soundfx/$V4ALIB
  cp -f $INSTALLER/custom/2.3/privapp-permissions-com.vipercn.viper4android_v2.xml $INSTALLER/system/etc/permissions/privapp-permissions-com.vipercn.viper4android_v2.xml
  cp -f $INSTALLER/custom/2.3/libV4AJniUtils_$JNI.so $INSTALLER/system/app/ViPER4AndroidFX/lib/$JNI/libV4AJniUtils.so
  cp -f $INSTALLER/custom/2.3/ViPER4AndroidFX.apk $INSTALLER/system/app/ViPER4AndroidFX/ViPER4AndroidFX.apk
  sed -ri "s/version=(.*)/version=\1 (2.3.4.0)/" $INSTALLER/module.prop
  $LATESTARTSERVICE && sed -i 's/<ACTIVITY>/com.vipercn.viper4android_v2/g' $INSTALLER/common/service.sh
  LIBPATCH="\/system"; LIBDIR=/system; DYNAMICOREO=false
fi

# Lib fix for pixel 2's and essential phone
if device_check "walleye" || device_check "taimen" || device_check "mata"; then
  if [ -f /system/lib/libstdc++.so ] && [ ! -f $VEN/lib/libstdc++.so ]; then
    cp_ch /system/lib/libstdc++.so $UNITY$VEN/lib/libstdc++.so
  elif [ -f $VEN/lib/libstdc++.so ] && [ ! -f /system/lib/libstdc++.so ]; then
    cp_ch $VEN/lib/libstdc++.so $UNITY/system/lib/libstdc++.so
  fi
fi

if $PATCH; then
  ui_print " "
  ui_print "   Patching existing audio_effects files..."
  for OFILE in ${CFGS}; do
    FILE="$UNITY$(echo $OFILE | sed "s|^/vendor|/system/vendor|g")"
    cp_ch $ORIGDIR$OFILE $FILE
    osp_detect $FILE
    case $FILE in
      *.conf) sed -i "/v4a_standard_fx {/,/}/d" $FILE
              sed -i "/v4a_fx {/,/}/d" $FILE
              sed -i "s/^effects {/effects {\n  v4a_standard_fx { #$MODID\n    library v4a_fx\n    uuid 41d3c987-e6cf-11e3-a88a-11aba5d5c51b\n  } #$MODID/g" $FILE
              sed -i "s/^libraries {/libraries {\n  v4a_fx { #$MODID\n    path $LIBPATCH\/lib\/soundfx\/$V4ALIB\n  } #$MODID/g" $FILE;;
      *.xml) sed -i "/v4a_standard_fx/d" $FILE
             sed -i "/v4a_fx/d" $FILE
             sed -i "/<libraries>/ a\        <library name=\"v4a_fx\" path=\"$V4ALIB\"\/><!--$MODID-->" $FILE
             sed -i "/<effects>/ a\        <effect name=\"v4a_standard_fx\" library=\"v4a_fx\" uuid=\"41d3c987-e6cf-11e3-a88a-11aba5d5c51b\"\/><!--$MODID-->" $FILE;;
    esac
  done
fi
