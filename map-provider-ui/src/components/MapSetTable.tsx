import { createColumnHelper, flexRender, getCoreRowModel, useReactTable } from "@tanstack/react-table";
import { useMemo } from "react";

import type { MapSetManifest } from "../types";


type MapSetTableProps = {
  rows: MapSetManifest[];
  activeDataset: string | null;
  onPreview: (path: string) => void;
  onActivate: (path: string) => void;
};


export function MapSetTable({ rows, activeDataset, onPreview, onActivate }: MapSetTableProps) {
  const columnHelper = createColumnHelper<MapSetManifest>();
  const columns = useMemo(
    () => [
      columnHelper.accessor("name", {
        header: "Map Set",
        cell: (info) => info.getValue()
      }),
      columnHelper.accessor("raster_files", {
        header: "Rasters",
        cell: (info) => info.getValue().length
      }),
      columnHelper.accessor("dtm_vrt", {
        header: "DTM VRT",
        cell: (info) => <code>{info.getValue()}</code>
      }),
      columnHelper.display({
        id: "actions",
        header: "Actions",
        cell: ({ row }) => (
          <div className="inline-actions">
            <button
              type="button"
              className="segment"
              disabled={row.original.raster_files.length === 0}
              onClick={() => onPreview(row.original.raster_files[0] ?? "")}
            >
              Preview
            </button>
            {row.original.dtm_vrt ? (
              <button
                type="button"
                className={activeDataset === row.original.dtm_vrt ? "segment active" : "segment"}
                onClick={() => onActivate(row.original.dtm_vrt!)}
              >
                {activeDataset === row.original.dtm_vrt ? "Active" : "Activate"}
              </button>
            ) : null}
          </div>
        )
      })
    ],
    [activeDataset, onActivate, onPreview]
  );

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel()
  });

  return (
    <div className="panel">
      <h2>Generated Map Sets</h2>
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
                <td colSpan={4} className="muted">No generated map sets yet.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </div>
  );
}
