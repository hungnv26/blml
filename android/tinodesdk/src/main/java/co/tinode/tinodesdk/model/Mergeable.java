package co.tinode.tinodesdk.model;

/*
 * Interface that allows merging of objects.
 */
public interface Mergeable {
    // Merges this with |another|.
    // Returns true if any field was modified.
    boolean merge(Mergeable another);
}
