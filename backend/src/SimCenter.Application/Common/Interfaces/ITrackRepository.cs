using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>Track 마스터 조회 포트. 게임 정수 트랙 ID → 도메인 Track 매핑.</summary>
public interface ITrackRepository
{
    Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default);

    /// <summary>PK로 트랙 조회. 랭킹 조회 시 트랙 검증/트랙명 확보.</summary>
    Task<Track?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>트랙 마스터 전체(04 §3.8). GameCode·Name 정렬.</summary>
    Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken cancellationToken = default);
}
