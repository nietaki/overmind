defmodule Overmind.ZnodeStat do
  @moduledoc """
  All fields of the struct are non-negative integers

  For fields' meanings see https://github.com/huaban/erlzk/blob/master/include/erlzk.hrl#L13-L25
  """

  @enforce_keys [
    # The zxid of the change that caused this znode to be created.
    :czxid,
    # The zxid of the change that last modified this znode.
    :mzxid,
    # The time in milliseconds from epoch when this znode was created.
    :ctime,
    # The time in milliseconds from epoch when this znode was last modified.
    :mtime,
    # The number of changes to the data of this znode.
    :version,
    # The number of changes to the children of this znode.
    :cversion,
    # The number of changes to the ACL of this znode.
    :aversion,
    # The session id of the owner of this znode if the znode is an ephemeral node. If it is not an ephemeral node, it will be zero.
    :ephemeral_owner,
    # The length of the data field of this znode.
    :data_length,
    # The number of children of this znode.
    :num_children,
    # The zxid of the change that last created or deleted the children of this znode.
    :pzxid
  ]

  defstruct @enforce_keys

  def new(
        {:stat, czxid, mzxid, ctime, mtime, version, cversion, aversion, ephemeral_owner,
         data_length, num_children, pzxid}
      ) do
    %__MODULE__{
      czxid: czxid,
      mzxid: mzxid,
      ctime: ctime,
      mtime: mtime,
      version: version,
      cversion: cversion,
      aversion: aversion,
      ephemeral_owner: ephemeral_owner,
      data_length: data_length,
      num_children: num_children,
      pzxid: pzxid
    }
  end
end
