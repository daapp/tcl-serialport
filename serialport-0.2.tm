package require Tcl 8.5
package require snit


snit::type serialport {
    option -port -default com1 -configuremethod SetPort
    option -mode -default ""   -configuremethod SetMode -cgetmethod GetMode
    option -ttycontrol -configuremethod SetTtyControl
    option -timeout 0
    option -eol \x0d
    option -translation {auto auto}
    # -debug commandPrefix
    # commandPrefix portName direction message
    # direction - "<" (into port) or ">" (from port)
    option -debug -default ""

    variable channel {}

    case $::tcl_platform(platform) {
        "windows" {
            package require registry

            typemethod getPorts {} {
                set serial_base "HKEY_LOCAL_MACHINE\\HARDWARE\\DEVICEMAP\\SERIALCOMM"
                set result {}

                catch {
                    set values [registry values $serial_base]

                    foreach valueName $values {
                        lappend result [registry get $serial_base $valueName]
                    }
                }

                return $result
            }
        }
        "unix" {
            case $::tcl_platform(os) {
                "Linux" {
                    typemethod getPorts {} {
                        set f [open /proc/tty/drivers r]
                        set lines [split [read $f] \n]
                        chan close $f

                        set ports [list]
                        foreach driver $lines {
                            if {[lindex $driver 4] eq "serial"} {
                                lappend ports {*}[glob -nocomplain "[lindex $driver 1]\[0-9\]*"]
                            }
                        }
                        return [lsort -dict $ports]
                    }
                }
            }
        }
    }


    constructor {args} {
        $self configurelist $args
    }


    destructor {
        catch {chan close $channel}
    }


    method SetPort {option value} {
        catch {chan close $channel}

        if {$value ne ""} {
            set channel [open $value {RDWR BINARY}]

            chan configure $channel \
                -blocking true \
                -translation binary \
                -encoding binary

            if {$options(-mode) ne ""} {
                $self SetMode -mode $options(-mode)
            }
        }

        set options($option) $value
    }


    method SetMode {option value} {
        if {$channel ne ""} {
            chan configure $channel \
                -mode $value
        }

        set options($option) $value
    }


    method GetMode {option} {
        if {$channel ne ""} {
            return [chan configure $channel -mode]
        } else {
            return
        }
    }


    method SetTtyControl {option value} {
        chan configure $channel -ttycontrol $value
    }


    ### public methods

    method clear {} {
        chan configure $channel -blocking false
        chan read $channel
        chan configure $channel -blocking true
    }


    method send {message} {
        chan puts -nonewline $channel $message
        chan flush $channel
        if {$options(-debug) ne ""} {
            uplevel #0 [linsert $options(-debug) end $options(-port) "<" $message]
        }
    }


    method sendline {message} {
        chan puts -nonewline $channel "$message$options(-eol)"
        # chan puts -nonewline "$message$options(-eol)"
        chan flush $channel
        if {$options(-debug) ne ""} {
            uplevel #0 [linsert $options(-debug) end $options(-port) "<" $message]
        }
    }


    method receive {{length 0}} {
        if {$length == 0} {
            set res ""
            chan configure $channel -translation $options(-translation)
            chan gets $channel res

            if {$options(-debug) ne ""} {
                uplevel #0 [linsert $options(-debug) end $options(-port) ">" $res]
            }

            return $res
        } else {
            chan configure $channel -translation binary
            set res [chan read $channel $length]

            if {$options(-debug) ne ""} {
                # todo: output in hex here
                uplevel #0 [linsert $options(-debug) end $options(-port) ">" $res]
            }

            return $res
        }
    }


    # args: -command cmd
    #       -buffer size - if buffer size is "line", then use line buffering
    #                         else it is a number of bytes for full buffering
    method asyncReceive {args} {
        if {[dict exists $args -command]} {
            set command [from args -command]
            if {$command eq ""} {
                # stop
                chan event $channel readable {}
                chan configure $channel -blocking true
                $self clear
            } else {
                $self clear
                set bufferSize [from args -buffersize line]
                if {$bufferSize eq "line"} {
                    chan configure $channel -buffering line -buffersize 4096
                } else {
                    chan configure $channel -buffering full -buffersize $bufferSize
                }
                chan event $channel readable $command
            }
        } else {
            return -code error "-command not specified"
        }
    }


    method eof {} {
        chan eof $channel
    }


    method event {args} {
        chan event $channel {*}$args
    }
}
