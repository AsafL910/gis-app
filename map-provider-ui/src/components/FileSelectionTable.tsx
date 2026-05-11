import { createColumnHelper, flexRender, getCoreRowModel, useReactTable } from "@tanstack/react-table";
import { useMemo } from "react";

import type { CatalogFile } from "../types";
import { formatBytes } from "../utils/raster";


type FileSelectionTableProps = {
  title: string;
  rows: CatalogFile[];
  selectedPaths: string[];
  onToggle: (path: string) => void;
};


export function FileSelectionTable({ title, rows, selectedPaths, onToggle }: FileSelectionTableProps) {
  const selectedSet = useMemo(() => new Set(selectedPaths), [selectedPaths]);
  const columnHelper = createColumnHelper<CatalogFile>();
  const columns = useMemo(
    () => [
      columnHelper.display({
        id: "select",
        header: "",
        cell: ({ row }) => (
          <input
            type="checkbox"
            checked={selectedSet.has(row.original.path)}
            onChange={() => onToggle(row.original.path)}
          />
        )
      }),
      columnHelper.accessor("name", {
        header: "Name",
        cell: (info) => info.getValue()
      }),
      columnHelper.accessor("path", {
        header: "Path",
        cell: (info) => <code>{info.getValue()}</code>
      }),
      columnHelper.accessor("size", {
        header: "Size",
        cell: (info) => formatBytes(info.getValue())
      })
    ],
    [columnHelper, onToggle, selectedSet]
  );

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel()
  });

  return (
    <div className="panel">
      <div className="panel-heading">
        <h2>{title}</h2>
        <span className="muted small">{selectedPaths.length} selected</span>
      </div>
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            {table.getHeaderGroups().map((headerGroup) => (
              <tr key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <th key={header.id}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(header.column.columnDef.header, header.getContext())}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map((row) => (
              <tr key={row.id}>
                {row.getVisibleCells().map((cell) => (
                  <td key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
            {rows.length === 0 ? (
              <tr>
                <td colSpan={4} className="muted">No files found.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </div>
  );
}
