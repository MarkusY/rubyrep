module RR

  # Provides helper functionality for replicators.
  # The methods exposed by this class are intended to provide a stable interface
  # for third party replicators.
  class ReplicationHelper

    # The current +ReplicationRun+ instance
    attr_accessor :replication_run

    # The active +Session+
    def session; replication_run.session; end

    # Current options
    def options; @options ||= session.configuration.options; end

    # Delegates to Session#corresponding_table
    def corresponding_table(db_arm, table); session.corresponding_table(db_arm, table); end

    # Delegates to Committer#insert_record
    def insert_record(database, table, values)
      committer.insert_record(database, table, values)
    end

    # Delegates to Committer#insert_record
    def update_record(database, table, values, old_key = nil)
      committer.update_record(database, table, values, old_key)
    end

    # Delegates to Committer#insert_record
    def delete_record(database, table, values)
      committer.delete_record(database, table, values)
    end

    # Loads the specified record. Returns an according column_name => value hash.
    # Parameters:
    # * +database+: either :+left+ or :+right+
    # * +table+: name of the table
    # * +key+: A column_name => value hash for all primary key columns.
    def load_record(database, table, key)
      query = session.send(database).table_select_query(table, :row_keys => [key])
      cursor = TypeCastingCursor.new(
        session.send(database), table,
        session.send(database).select_cursor(query)
      )
      row = nil
      row = cursor.next_row if cursor.next?
      cursor.clear
      row
    end

    # The current Committer
    attr_reader :committer
    private :committer

    # Asks the committer (if it exists) to finalize any open transactions
    # +success+ should be true if there were no problems, false otherwise.
    def finalize(success = true)
      committer.finalize(success)
    end

    # Logs the outcome of a replication into the replication log table.
    # * +diff+: the replicated ReplicationDifference
    # * +outcome+: string summarizing the outcome of the replication
    # * +details+: string with further details regarding the replication
    def log_replication_outcome(diff, outcome, details = nil)
      table = diff.changes[:left].table
      key = diff.changes[:left].key
      key = key.size == 1 ? key.values[0] : key.inspect
      rep_details = details == nil ? nil : details[0...ReplicationInitializer::REP_DETAILS_SIZE]
      diff_dump = diff.to_yaml[0...ReplicationInitializer::DIFF_DUMP_SIZE]
      
      session.left.insert_record "#{options[:rep_prefix]}_event_log", {
        :activity => 'replication',
        :rep_table => table,
        :diff_type => diff.type.to_s,
        :diff_key => key,
        :left_change_type => (diff.changes[:left] ? diff.changes[:left].type.to_s : nil),
        :right_change_type => (diff.changes[:right] ? diff.changes[:right].type.to_s : nil),
        :rep_outcome => outcome,
        :rep_details => rep_details,
        :rep_time => Time.now,
        :diff_dump => diff_dump
      }
    end
    
    # Creates a new SyncHelper for the given +TableSync+ instance.
    def initialize(replication_run)
      self.replication_run = replication_run

      # Creates the committer. Important as it gives the committer the
      # opportunity to start transactions
      committer_class = Committers::committers[options[:committer]]
      @committer = committer_class.new(session)
    end
  end
end