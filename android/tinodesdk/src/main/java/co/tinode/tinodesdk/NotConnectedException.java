package co.tinode.tinodesdk;

/**
 * Attempt to perform an operation while not connected to the server.
 */
public class NotConnectedException extends IllegalStateException {

    public NotConnectedException() {
        this((Throwable) null);
    }

    public NotConnectedException(String s) {
        this(s, null);
    }

    public NotConnectedException(String message, Throwable cause) {
        super(message, cause);
    }

    public NotConnectedException(Throwable cause) {
        this("Not connected", cause);
    }
}
