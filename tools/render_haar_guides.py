#!/usr/bin/env python3
"""Render generated research guide curves and the unchanged upstream head."""
import argparse
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Line3DCollection, Poly3DCollection
from safetensors.torch import load_file
from haar_decode_metal import read_obj


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('strands', type=Path)
    parser.add_argument('head', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--title', default='Metal-generated hair guides')
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Use a new preview path')
    strands = load_file(str(args.strands))['strands'].numpy()
    vertices, faces = read_obj(args.head)
    # Plot X/right, Z/depth, Y/up without altering exported geometry.
    curves = strands[:, :, [0, 2, 1]]
    mesh = vertices[:, [0, 2, 1]]
    # Include the head, excluding lower neck/torso from preview framing.
    minimum = np.minimum(curves.min(axis=(0, 1)), mesh.max(axis=0) - np.array([.3, .3, .32]))
    maximum = np.maximum(curves.max(axis=(0, 1)), mesh.max(axis=0))
    center = (minimum + maximum) / 2
    span = max(maximum - minimum) * 1.08
    fig = plt.figure(figsize=(14, 5.4), facecolor='#f5f2ed')
    for index, (label, azimuth) in enumerate([('Front', 90), ('Side', 0), ('Back', -90)]):
        ax = fig.add_subplot(1, 3, index + 1, projection='3d', computed_zorder=False)
        ax.set_facecolor('#f5f2ed')
        ax.add_collection3d(Poly3DCollection(mesh[faces], facecolors='#c6c0b5', edgecolors='#c6c0b5',
            linewidths=0, shade=True, zorder=1))
        ax.add_collection3d(Line3DCollection(curves, colors='#332722', linewidths=.45, alpha=.8, zorder=2))
        ax.set(xlim=(center[0]-span/2, center[0]+span/2), ylim=(center[1]-span/2, center[1]+span/2),
               zlim=(center[2]-span/2, center[2]+span/2))
        ax.set_box_aspect((1, 1, 1))
        ax.set_proj_type('ortho')
        ax.view_init(elev=5, azim=azimuth)
        ax.set_axis_off()
        ax.set_title(label, color='#252525', fontsize=12)
    fig.suptitle(args.title, fontsize=19, color='#252525', y=.98)
    fig.text(.5, .025, f'{len(strands)} guide curves · Template head · Diagnostic curves show through the head · Not personalized',
             ha='center', fontsize=10, color='#48433e')
    fig.subplots_adjust(top=.88, bottom=.09, left=.01, right=.99, wspace=0)
    fig.savefig(args.output, dpi=160, facecolor=fig.get_facecolor())
    plt.close(fig)


if __name__ == '__main__':
    main()
